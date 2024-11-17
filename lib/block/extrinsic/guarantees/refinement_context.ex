defmodule RefinementContext do
  alias Util.Hash

  @type t :: %__MODULE__{
          # a - anchor header hash
          anchor: Types.hash(),
          # s
          state_root_: Types.hash(),
          # b
          beefy_root_: Types.hash(),
          # l - lookup anchor header hash
          lookup_anchor: Types.hash(),
          # t
          timeslot: Types.timeslot(),
          # p
          prerequisite: MapSet.t(Types.hash())
        }

  # Formula (120) v0.4.5
  # a - anchor header hash
  defstruct anchor: Hash.zero(),
            # s - posterior state root
            state_root_: Hash.zero(),
            # b - posterior beefy root
            beefy_root_: Hash.zero(),
            # l - lookup anchor header hash
            lookup_anchor: Hash.zero(),
            # t
            timeslot: 0,
            # p
            prerequisite: MapSet.new()

  defimpl Encodable do
    alias Codec.{Encoder, VariableSize}

    # Formula (311) v0.4.5
    def encode(%RefinementContext{
          anchor: a,
          state_root_: s,
          beefy_root_: b,
          lookup_anchor: l,
          timeslot: t,
          prerequisite: p
        }) do
      Encoder.encode({a, s, b, l}) <>
        Encoder.encode_le(t, 4) <> Encoder.encode(VariableSize.new(p))
    end
  end

  use Sizes
  use Codec.Decoder

  def decode(bin) do
    alias Codec.VariableSize

    <<anchor::binary-size(@hash_size), state_root_::binary-size(@hash_size),
      beefy_root_::binary-size(@hash_size), lookup_anchor::binary-size(@hash_size),
      timeslot::binary-size(4), temp_rest::binary>> = bin

    {prerequisite, rest} = VariableSize.decode(temp_rest, :mapset, @hash_size)

    {
      %__MODULE__{
        anchor: anchor,
        state_root_: state_root_,
        beefy_root_: beefy_root_,
        lookup_anchor: lookup_anchor,
        timeslot: de_le(timeslot, 4),
        prerequisite: prerequisite
      },
      rest
    }
  end

  use JsonDecoder

  def json_mapping do
    %{
      state_root_: :state_root,
      beefy_root_: :beefy_root,
      timeslot: :lookup_anchor_slot,
      prerequisite: fn p -> if(p == nil, do: MapSet.new([]), else: p) end
    }
  end
end
