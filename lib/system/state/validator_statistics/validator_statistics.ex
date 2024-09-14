defmodule System.State.ValidatorStatistics do
  @moduledoc """
  Formula (171) v0.3.4
  Tracks validator statistics on a per-epoch basis.

  The validator statistics are made on a per-epoch basis and are retained as a
  sequence of two elements:
  - The first element is an accumulator for the present epoch.
  - The second element is the previous epoch's statistics.

  For each epoch, we track the following six statistics:
  - `blocks_produced` (`b`): The number of blocks produced by the validator.
  - `tickets_introduced` (`t`): The number of tickets introduced by the validator.
  - `preimages_introduced` (`p`): The number of preimages introduced by the validator.
  - `data_size` (`d`): The total number of octets across all preimages introduced by the validator.
  - `reports_guaranteed` (`g`): The number of reports guaranteed by the validator.
  - `availability_assurances` (`a`): The number of availability assurances made by the validator.
  """
  alias Block.Extrinsic.Guarantee
  alias Block.{Extrinsic, Header}
  alias System.State.{Validator, ValidatorStatistic, ValidatorStatistics}
  alias Util.Time

  @type t :: %__MODULE__{
          current_epoch_statistics: list(ValidatorStatistic.t()),
          previous_epoch_statistics: list(ValidatorStatistic.t())
        }

  def new_epoc_stats do
    Enum.map(1..Constants.validator_count(), fn _ -> %ValidatorStatistic{} end)
  end

  defstruct current_epoch_statistics: [],
            previous_epoch_statistics: []

  @callback posterior_validator_statistics(
              Extrinsic.t(),
              integer(),
              ValidatorStatistics.t(),
              list(Validator.t()),
              Header.t()
            ) :: ValidatorStatistics.t()
  def posterior_validator_statistics(
        %Extrinsic{} = extrinsic,
        timeslot,
        %ValidatorStatistics{} = validator_statistics,
        new_curr_validators,
        %Header{} = header
      ) do
    # Formula (172) v0.3.4
    # Formula (173) v0.3.4
    {new_current_epoc_stats, new_previous_epoc_stats} =
      case Time.new_epoch?(timeslot, header.timeslot) do
        {:ok, true} ->
          {new_epoc_stats(), validator_statistics.current_epoch_statistics}

        {:ok, false} ->
          {validator_statistics.current_epoch_statistics,
           validator_statistics.previous_epoch_statistics}
      end

    author_stats =
      Enum.at(new_current_epoc_stats, header.block_author_key_index)

    if author_stats == nil, do: raise(ArgumentError, "Author statistics not found")

    # Formula (174) v0.3.4
    new_author_stats = %{
      author_stats
      | blocks_produced: author_stats.blocks_produced + 1,
        tickets_introduced: author_stats.tickets_introduced + length(extrinsic.tickets),
        preimages_introduced: author_stats.preimages_introduced + length(extrinsic.preimages),
        data_size:
          author_stats.data_size +
            (extrinsic.preimages
             |> Enum.map(&byte_size(&1.data))
             |> Enum.sum())
    }

    new_current_epoc_stats =
      new_current_epoc_stats
      |> List.replace_at(header.block_author_key_index, new_author_stats)
      |> Enum.with_index()
      |> Enum.map(fn {stats, index} ->
        %{
          stats
          | availability_assurances:
              stats.availability_assurances +
                (extrinsic.assurances
                 |> Enum.any?(&(&1.validator_index == index))
                 |> if(do: 1, else: 0)),
            # π'0[v]a ≡ a[v]a + (∃a ∈ EA ∶ av = v)
            reports_guaranteed:
              author_stats.reports_guaranteed +
                (Guarantee.reporters_set(extrinsic.guarantees)
                 |> Enum.any?(&(&1 == Enum.at(index, new_curr_validators)))
                 |> if(do: 1, else: 0))
        }
      end)

    %ValidatorStatistics{
      current_epoch_statistics: new_current_epoc_stats,
      previous_epoch_statistics: new_previous_epoc_stats
    }
  end

  defimpl Encodable do
    alias System.State.{ValidatorStatistic, ValidatorStatistics}

    def encode(%ValidatorStatistics{} = v) do
      Codec.Encoder.encode({
        v.current_epoch_statistics |> Enum.map(&Codec.Encoder.encode/1),
        v.previous_epoch_statistics |> Enum.map(&Codec.Encoder.encode/1)
      })
    end
  end
end
