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
          prerequisite: Types.hash() | nil
        }

  # Formula (120) v0.4.1
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
            prerequisite: Hash.zero()

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

  use JsonDecoder

  def json_mapping do
    %{state_root_: :state_root, beefy_root_: :beefy_root, timeslot: :lookup_anchor_slot}
  end
end
