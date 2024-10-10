defmodule RefinementContext do
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
          prerequisite: Types.hash() | nil
        }

  # Formula (120) v0.4.1
  # a - anchor header hash
  defstruct anchor: <<0::256>>,
            # s - posterior state root
            state_root_: <<0::256>>,
            # b - posterior beefy root
            beefy_root_: <<0::256>>,
            # l - lookup anchor header hash
            lookup_anchor: <<0::256>>,
            # t
            timeslot: 0,
            # p
            prerequisite: <<0::256>>

  defimpl Encodable do
    alias Codec.{Encoder, NilDiscriminator}

    # Formula (304) v0.4.1
    def encode(%RefinementContext{
          anchor: a,
          state_root_: s,
          beefy_root_: b,
          lookup_anchor: l,
          timeslot: t,
          prerequisite: p
        }) do
      Encoder.encode({a, s, b, l}) <>
        Encoder.encode_le(t, 4) <> Encoder.encode(NilDiscriminator.new(p))
    end
  end
end
