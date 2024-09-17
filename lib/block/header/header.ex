defmodule Block.Header do
  alias Codec.{NilDiscriminator, VariableSize}
  alias System.State.SealKeyTicket
  alias Util.Time

  @type t :: %__MODULE__{
          # Formula (38) v0.3.4
          # Hp
          parent_hash: Types.hash(),
          # Formula (42) v0.3.4
          # Hr
          prior_state_root: Types.hash(),
          # Formula (40) v0.3.4
          # Hx
          extrinsic_hash: Types.hash(),
          # Formula (41) v0.3.4
          # Ht
          timeslot: integer(),
          # Formula (44) v0.3.4
          # He
          epoch: {Types.hash(), list(Types.bandersnatch_key())} | nil,
          # Hw
          winning_tickets_marker: list(SealKeyTicket.t()) | nil,
          # Formula (45) v0.3.4
          # Hj
          judgements_marker: list(Types.hash()),
          # Ho
          offenders_marker: list(Types.hash()),
          # Formula (43) v0.3.4
          # Hi
          block_author_key_index: Types.validator_index(),
          # Hv
          vrf_signature: binary(),
          # Hs
          block_seal: binary()
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
    epoch: nil,
    # Hw
    winning_tickets_marker: nil,
    # Hj
    judgements_marker: [],
    # Ho
    offenders_marker: [],
    # Hi
    block_author_key_index: 0,
    # Hv
    vrf_signature: <<>>,
    # Hs
    block_seal: <<>>
  ]

  @spec validate(t(), System.State.t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{timeslot: current_timeslot}, %System.State{timeslot: previous_timeslot}) do
    with :ok <- Time.validate_timeslot_order(previous_timeslot, current_timeslot),
         # Formula (41)
         :ok <- Time.validate_block_timeslot(current_timeslot) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Formula (40) v0.3.4
  def valid_extrinsic_hash?(header, extrinsic) do
    header.extrinsic_hash == Util.Hash.default(Codec.Encoder.encode(extrinsic))
  end

  def valid_header?(_, %Block.Header{parent_hash: nil} = h) do
    Time.valid_block_timeslot?(h.timeslot)
  end

  def valid_header?(storage, header) do
    case storage[header.parent_hash] do
      nil ->
        false

      parent_header ->
        parent_header.timeslot < header.timeslot and
          Time.valid_block_timeslot?(header.timeslot)
    end
  end

  # Formula (282) v0.3.4
  def unsigned_serialize(%Block.Header{} = header) do
    Codec.Encoder.encode({header.parent_hash, header.prior_state_root, header.extrinsic_hash}) <>
      Codec.Encoder.encode_le(header.timeslot, 4) <>
      Codec.Encoder.encode(
        {NilDiscriminator.new(header.epoch), NilDiscriminator.new(header.winning_tickets_marker),
         VariableSize.new(header.judgements_marker), VariableSize.new(header.offenders_marker),
         Codec.Encoder.encode_le(header.block_author_key_index, 2), header.vrf_signature}
      )
  end

  defimpl Encodable do
    # Formula (281) v0.3.4
    def encode(%Block.Header{} = header) do
      Block.Header.unsigned_serialize(header) <> Codec.Encoder.encode(header.block_seal)
    end
  end
end
