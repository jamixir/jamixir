defmodule RefinementContext do
  alias Util.Hash

  @type t :: %__MODULE__{
          # a - anchor header hash
          anchor: Types.hash(),
          # s
          state_root: Types.hash(),
          # b
          beefy_root: Types.hash(),
          # l - lookup anchor header hash
          lookup_anchor: Types.hash(),
          # t
          timeslot: Types.timeslot(),
          # p
          prerequisite: MapSet.t(Types.hash())
        }

  # Formula (11.4) v0.6.0
  # a - anchor header hash
  defstruct anchor: Hash.zero(),
            # s - posterior state root
            state_root: Hash.zero(),
            # b - posterior beefy root
            beefy_root: Hash.zero(),
            # l - lookup anchor header hash
            lookup_anchor: Hash.zero(),
            # t
            timeslot: 0,
            # p
            prerequisite: MapSet.new()

  defimpl Encodable do
    alias Codec.{Encoder, VariableSize}
    use Codec.Encoder
    # Formula (C.21) v0.6.0
    def encode(%RefinementContext{
          anchor: a,
          state_root: s,
          beefy_root: b,
          lookup_anchor: l,
          timeslot: t,
          prerequisite: p
        }) do
      e({a, s, b, l}) <> <<t::32-little>> <> e(vs(p))
    end
  end

  use Sizes
  use Codec.Decoder

  def decode(bin) do
    alias Codec.VariableSize

    <<anchor::binary-size(@hash_size), state_root::binary-size(@hash_size),
      beefy_root::binary-size(@hash_size), lookup_anchor::binary-size(@hash_size),
      timeslot::32-little, temp_rest::binary>> = bin

    {prerequisite, rest} = VariableSize.decode(temp_rest, :mapset, @hash_size)

    {
      %__MODULE__{
        anchor: anchor,
        state_root: state_root,
        beefy_root: beefy_root,
        lookup_anchor: lookup_anchor,
        timeslot: timeslot,
        prerequisite: prerequisite
      },
      rest
    }
  end

  use JsonDecoder

  def json_mapping do
    %{
      timeslot: :lookup_anchor_slot,
      prerequisite: [&process_prerequisite/1, :prerequisites]
    }
  end

  def to_json_mapping,
    do: %{
      timeslot: :lookup_anchor_slot
    }

  def process_prerequisite(p) do
    if(p == nil, do: [], else: JsonDecoder.from_json(p)) |> MapSet.new()
  end
end
