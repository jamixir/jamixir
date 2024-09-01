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
  alias Util.Time
  alias Block.Header
  alias System.State.ValidatorStatistics
  alias Block.Extrinsic

  @type validator_statistics :: %{
          # b
          blocks_produced: non_neg_integer(),
          # t
          tickets_introduced: non_neg_integer(),
          # p
          preimages_introduced: non_neg_integer(),
          # d
          data_size: non_neg_integer(),
          # g
          reports_guaranteed: non_neg_integer(),
          # a
          availability_assurances: non_neg_integer()
        }

  @type t :: %__MODULE__{
          current_epoch_statistics: list(validator_statistics()),
          previous_epoch_statistics: list(validator_statistics())
        }

  def zeroed_statistic do
    %{
      blocks_produced: 0,
      tickets_introduced: 0,
      preimages_introduced: 0,
      data_size: 0,
      reports_guaranteed: 0,
      availability_assurances: 0
    }
  end

  def new_epoc_stats do
    Enum.map(1..Constants.validator_count(), fn _ -> zeroed_statistic() end)
  end

  def statistic(b, t, p, d, g, a) do
    %{
      blocks_produced: b,
      tickets_introduced: t,
      preimages_introduced: p,
      data_size: d,
      reports_guaranteed: g,
      availability_assurances: a
    }
  end

  defstruct current_epoch_statistics: [],
            previous_epoch_statistics: []

  def posterior_validator_statistics(
        %Extrinsic{} = extrinsic,
        timeslot,
        %ValidatorStatistics{} = validator_statistics,
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
             |> Enum.sum()),
        # π'0[v]a ≡ a[v]a + (∃a ∈ EA ∶ av = v)
        availability_assurances:
          author_stats.availability_assurances +
            (extrinsic.assurances
             |> Enum.any?(&(&1.validator_index == header.block_author_key_index))
             |> if(do: 1, else: 0))
    }

    new_current_epoc_stats =
      List.replace_at(new_current_epoc_stats, header.block_author_key_index, new_author_stats)

    %ValidatorStatistics{
      current_epoch_statistics: new_current_epoc_stats,
      previous_epoch_statistics: new_previous_epoc_stats
    }
  end

  defimpl Encodable do
    alias System.State.ValidatorStatistics

    def encode(%ValidatorStatistics{} = v) do
      Codec.Encoder.encode({
        v.current_epoch_statistics |> Enum.map(&encode_single_statistic/1),
        v.previous_epoch_statistics |> Enum.map(&encode_single_statistic/1)
      })
    end

    defp encode_single_statistic(%{
           blocks_produced: b,
           tickets_introduced: t,
           preimages_introduced: p,
           data_size: d,
           reports_guaranteed: g,
           availability_assurances: a
         }) do
      [b, t, p, d, g, a]
      |> Enum.map(&Codec.Encoder.encode_le(&1, 4))
    end
  end
end
