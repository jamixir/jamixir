defmodule Block.Header do
  alias Codec.{NilDiscriminator, VariableSize}

  @type t :: %__MODULE__{
          parent_hash: Types.hash(), #Hp
          prior_state_root: Types.hash(), #Hr
          extrinsic_hash: Types.hash(), #Hx
          timeslot: integer(), #Ht
          epoch: integer() | nil, #He
          winning_tickets_marker: list(binary()) | nil, #Hw
          judgements_marker: list(binary()) | nil, #Hj
          o: list(binary()) | nil, #Ho
          block_author_key_index: Types.max_validators(), #Hi
          vrf_signature: binary(), #Hv
          block_seal: binary() #Hs
        }

  # Formula (37) v0.3.4
  defstruct [
    # Hp
    parent_hash: <<0::256>>,
    # Hr
    prior_state_root: nil,
    # Hx
    extrinsic_hash: <<0::256>>,
    # Ht
    timeslot: 0,
    # He
    epoch: 0,
    # Hw
    winning_tickets_marker: [],
    # Hj
    judgements_marker: [],
    # Ho
    o: [],
    # Hi
    block_author_key_index: 0,
    # Hv
    vrf_signature: nil,
    # Hs
    block_seal: <<>>
  ]

  # Formula 40 v0.3.4
  def valid_extrinsic_hash?(header, extrinsic) do
    header.extrinsic_hash == Util.Hash.default(Codec.Encoder.encode(extrinsic))
  end

  def valid_header?(_, h = %Block.Header{parent_hash: nil}) do
    Util.Time.valid_block_timeslot?(h.timeslot)
  end

  def valid_header?(storage, header) do
    case storage[header.parent_hash] do
      nil ->
        false

      parent_header ->
        parent_header.timeslot < header.timeslot and
          Util.Time.valid_block_timeslot?(header.timeslot)
    end
  end

  def unsigned_serialize(%Block.Header{} = header) do
    Codec.Encoder.encode({header.parent_hash, header.prior_state_root, header.extrinsic_hash}) <>
      Codec.Encoder.encode_le(header.timeslot, 4) <>
      Codec.Encoder.encode(
        {NilDiscriminator.new(header.epoch),
        NilDiscriminator.new(header.winning_tickets_marker),
        VariableSize.new(header.judgements_marker),
        VariableSize.new(header.o),
        Codec.Encoder.encode_le(header.block_author_key_index,2),
        header.vrf_signature,
      }
      )
  end

  defimpl Encodable do
    # Formula (281) v0.3.4
    def encode(%Block.Header{} = header) do
      Block.Header.unsigned_serialize(header) <> Codec.Encoder.encode(header.block_seal)
    end
  end
end
