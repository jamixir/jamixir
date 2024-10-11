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

  def from_json(json_data) do
    json = json_data |> Utils.hex_to_binary()

    %__MODULE__{
      anchor: json.anchor,
      state_root_: json.state_root,
      beefy_root_: json.beefy_root,
      lookup_anchor: json.lookup_anchor,
      timeslot: json.lookup_anchor_slot,
      prerequisite: json.prerequisite
    }
  end
end
