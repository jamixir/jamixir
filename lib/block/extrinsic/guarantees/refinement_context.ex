defmodule RefinementContext do
  @type t :: %__MODULE__{
          # a - anchor header hash
          anchor: Types.hash(),
          # s
          posterior_state_root: Types.hash(),
          # b
          posterior_beefy_root: Types.hash(),
          # l - lookup anchor header hash
          lookup_anchor: Types.hash(),
          # t
          timeslot: Types.timeslot(),
          # p
          prerequisite: Types.hash() | nil
        }

  # Formula (121) v0.3.4
  # a - anchor header hash
  defstruct anchor: <<0::256>>,
            # s
            posterior_state_root: <<0::256>>,
            # b
            posterior_beefy_root: <<0::256>>,
            # l - lookup anchor header hash
            lookup_anchor: <<0::256>>,
            # t
            timeslot: 0,
            prerequisite: <<0::256>>

  defimpl Encodable do
    alias Codec.{Encoder, NilDiscriminator}

    # Formula (283) v0.3.4
    def encode(%RefinementContext{
          anchor: a,
          posterior_state_root: s,
          posterior_beefy_root: b,
          lookup_anchor: l,
          timeslot: t,
          prerequisite: p
        }) do
      Encoder.encode({a, s, b, l}) <>
        Encoder.encode_le(t, 4) <> Encoder.encode(NilDiscriminator.new(p))
    end
  end
end
