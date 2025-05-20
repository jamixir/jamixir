defmodule System.State.ValidatorStatistic do
  @moduledoc """
  Formula (13.2) v0.6.5
  """
  defstruct blocks_produced: 0,
            tickets_introduced: 0,
            preimages_introduced: 0,
            da_load: 0,
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
          da_load: non_neg_integer(),
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
        e_le(v.da_load, 4),
        e_le(v.reports_guaranteed, 4),
        e_le(v.availability_assurances, 4)
      ]
    end
  end

  def decode(<<
        blocks_produced::little-32,
        tickets_introduced::little-32,
        preimages_introduced::little-32,
        da_load::little-32,
        reports_guaranteed::little-32,
        availability_assurances::little-32,
        rest::binary
      >>) do
    {%__MODULE__{
       blocks_produced: blocks_produced,
       tickets_introduced: tickets_introduced,
       preimages_introduced: preimages_introduced,
       da_load: da_load,
       reports_guaranteed: reports_guaranteed,
       availability_assurances: availability_assurances
     }, rest}
  end

  use JsonDecoder

  def json_mapping do
    %{
      blocks_produced: :blocks,
      tickets_introduced: :tickets,
      preimages_introduced: :pre_images,
      da_load: :pre_images_size,
      reports_guaranteed: :guarantees,
      availability_assurances: :assurances
    }
  end

  def to_json_mapping, do: json_mapping()
end
