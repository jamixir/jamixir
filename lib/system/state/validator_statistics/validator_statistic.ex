defmodule System.State.ValidatorStatistic do
  defstruct blocks_produced: 0,
            tickets_introduced: 0,
            preimages_introduced: 0,
            data_size: 0,
            reports_guaranteed: 0,
            availability_assurances: 0

  @type t :: %__MODULE__{
          blocks_produced: non_neg_integer(),
          tickets_introduced: non_neg_integer(),
          preimages_introduced: non_neg_integer(),
          data_size: non_neg_integer(),
          reports_guaranteed: non_neg_integer(),
          availability_assurances: non_neg_integer()
        }

  defimpl Encodable do
    def encode(%System.State.ValidatorStatistic{} = v) do
      [
        v.blocks_produced,
        v.tickets_introduced,
        v.preimages_introduced,
        v.data_size,
        v.reports_guaranteed,
        v.availability_assurances
      ]
      |> Enum.map_join(&Codec.Encoder.encode_le(&1, 4))
    end
  end
end
