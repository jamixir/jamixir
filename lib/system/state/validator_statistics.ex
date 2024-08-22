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
  - `octets_total` (`d`): The total number of octets across all preimages introduced by the validator.
  - `reports_guaranteed` (`g`): The number of reports guaranteed by the validator.
  - `availability_assurances` (`a`): The number of availability assurances made by the validator.
  """

  @type validator_statistics :: %{
          # b
          blocks_produced: non_neg_integer(),
          # t
          tickets_introduced: non_neg_integer(),
          # p
          preimages_introduced: non_neg_integer(),
          # d
          octets_total: non_neg_integer(),
          # g
          reports_guaranteed: non_neg_integer(),
          # a
          availability_assurances: non_neg_integer()
        }

  @type t :: %__MODULE__{
          current_epoch_statistics: list(validator_statistics()),
          previous_epoch_statistics: list(validator_statistics())
        }

  defstruct current_epoch_statistics: [],
            previous_epoch_statistics: []

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
           octets_total: d,
           reports_guaranteed: g,
           availability_assurances: a
         }) do
      [b, t, p, d, g, a]
      |> Enum.map(&Codec.Encoder.encode_le(&1, 4))
    end
  end
end
