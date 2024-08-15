defmodule RefinementContext do

  @type t :: %__MODULE__{
          # a
          anchor_header_hash: Types.hash(),
          # s
          state_root: Types.hash(),
          # b
          beefy_root: Types.hash(),
          # l
          lookup_header_hash: Types.hash(),
          # t
          timeslot: Types.timeslot(),
          # p
          prerequisite: Types.hash()
        }

  defstruct anchor_header_hash: <<0::256>>, # a
            state_root: <<0::256>>, # s
            beefy_root: <<0::256>>, # b
            lookup_header_hash: <<0::256>>, # l
            timeslot: 0, # t
            prerequisite: <<0::256>>

  defimpl Encodable do
    alias Codec.{Encoder, NilDiscriminator}

    def encode(%RefinementContext{
      anchor_header_hash: a,
      state_root: s,
      beefy_root: b,
      lookup_header_hash: l,
      timeslot: t,
      prerequisite: p}) do
      Encoder.encode({a,s,b,l}) <> Encoder.encode_le(t, 4) <> Encoder.encode(NilDiscriminator.new(p))
    end
  end
end
