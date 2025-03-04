defmodule System.State.ValidatorStatistics do
  @moduledoc """
  Formula (13.1) v0.6.2
  """
  alias Block.{Extrinsic, Header}
  alias System.State.{Validator, ValidatorStatistic}
  alias Util.Time

  @type t :: %__MODULE__{
          current_epoch_statistics: list(ValidatorStatistic.t()),
          previous_epoch_statistics: list(ValidatorStatistic.t())
        }

  def empty_epoc_stats do
    for _ <- 1..Constants.validator_count(), do: %ValidatorStatistic{}
  end

  @empty_epoch_stats for _ <- 1..Constants.validator_count(), do: %ValidatorStatistic{}

  defstruct current_epoch_statistics: @empty_epoch_stats,
            previous_epoch_statistics: @empty_epoch_stats

  @callback do_transition(
              Extrinsic.t(),
              integer(),
              __MODULE__.t(),
              list(Validator.t()),
              Header.t(),
              list(Types.ed25519_key())
            ) :: {:ok | :error, __MODULE__.t()}

  def transition(
        %Extrinsic{} = extrinsic,
        timeslot,
        %__MODULE__{} = validator_statistics,
        curr_validators_,
        %Header{} = header,
        reporters_set
      ) do
    module = Application.get_env(:jamixir, :validator_statistics, __MODULE__)

    module.do_transition(
      extrinsic,
      timeslot,
      validator_statistics,
      curr_validators_,
      header,
      reporters_set
    )
  end

  def do_transition(
        %Extrinsic{} = extrinsic,
        timeslot,
        %__MODULE__{} = validator_statistics,
        curr_validators_,
        %Header{} = header,
        reporters_set
      ) do
    # Formula (13.2) v0.6.0
    # Formula (13.3) v0.6.0
    {current_epoc_stats_, previous_epoc_stats_} =
      if Time.new_epoch?(timeslot, header.timeslot) do
        {empty_epoc_stats(), validator_statistics.current_epoch_statistics}
      else
        {validator_statistics.current_epoch_statistics,
         validator_statistics.previous_epoch_statistics}
      end

    case get_author_stats(current_epoc_stats_, header.block_author_key_index) do
      {:ok, author_stats} ->
        edkeys = curr_validators_ |> Enum.map(& &1.ed25519)
        # Formula (13.4) v0.6.0
        author_stats_ = %{
          author_stats
          | blocks_produced: author_stats.blocks_produced + 1,
            tickets_introduced: author_stats.tickets_introduced + length(extrinsic.tickets),
            preimages_introduced: author_stats.preimages_introduced + length(extrinsic.preimages),
            data_size:
              author_stats.data_size +
                Enum.sum(for preimage <- extrinsic.preimages, do: byte_size(preimage.blob))
        }

        current_epoc_stats_ =
          current_epoc_stats_
          |> List.replace_at(header.block_author_key_index, author_stats_)
          |> Enum.with_index()
          |> Enum.map(fn {stats, index} ->
            %{
              stats
              | # π'0[v]a ≡ a[v]a + (∃a ∈ EA ∶ av = v)
                availability_assurances:
                  stats.availability_assurances +
                    (extrinsic.assurances
                     |> Enum.any?(&(&1.validator_index == index))
                     |> if(do: 1, else: 0)),
                # π0[v]g ≡ a[v]g +(κ'v ∈ R)
                reports_guaranteed:
                  author_stats.reports_guaranteed +
                    (reporters_set
                     |> Enum.any?(&(&1 == Enum.at(edkeys, index)))
                     |> if(do: 1, else: 0))
            }
          end)

        {:ok,
         %__MODULE__{
           current_epoch_statistics: current_epoc_stats_,
           previous_epoch_statistics: previous_epoc_stats_
         }}

      {:error, e} ->
        {:error, e}
    end
  end

  defp get_author_stats(current_epoc_stats, author_key_index) do
    case Enum.at(current_epoc_stats, author_key_index) do
      nil -> {:error, :author_stats_not_found}
      stats -> {:ok, stats}
    end
  end

  def from_json(json_data) do
    %__MODULE__{
      current_epoch_statistics: Enum.map(json_data[:current], &ValidatorStatistic.from_json/1),
      previous_epoch_statistics: Enum.map(json_data[:last], &ValidatorStatistic.from_json/1)
    }
  end

  def to_json_mapping, do: %{current_epoch_statistics: :current, previous_epoch_statistics: :last}

  defimpl Encodable do
    alias System.State.{ValidatorStatistic, ValidatorStatistics}
    use Codec.Encoder

    def encode(%ValidatorStatistics{} = v) do
      e({
        for(s <- v.current_epoch_statistics, do: e(s)),
        for(s <- v.previous_epoch_statistics, do: e(s))
      })
    end
  end
end
