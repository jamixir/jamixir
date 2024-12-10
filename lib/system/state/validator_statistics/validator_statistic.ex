defmodule System.State.ValidatorStatistic do
  defstruct blocks_produced: 0,
            tickets_introduced: 0,
            preimages_introduced: 0,
            data_size: 0,
            reports_guaranteed: 0,
            availability_assurances: 0

  @type t :: %__MODULE__{
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

  defimpl Encodable do
    use Codec.Encoder

    def encode(%System.State.ValidatorStatistic{} = v) do
      [
        e_le(v.blocks_produced, 4),
        e_le(v.tickets_introduced, 4),
        e_le(v.preimages_introduced, 4),
        e_le(v.data_size, 4),
        e_le(v.reports_guaranteed, 4),
        e_le(v.availability_assurances, 4)
      ]
    end
  end

  use JsonDecoder

  def json_mapping do
    %{
      blocks_produced: :blocks,
      tickets_introduced: :tickets,
      preimages_introduced: :pre_images,
      data_size: :pre_images_size,
      reports_guaranteed: :guarantees,
      availability_assurances: :assurances
    }
  end
end
