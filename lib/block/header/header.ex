defmodule Block.Header do
  alias Codec.{NilDiscriminator, VariableSize}
  alias System.State.SealKeyTicket
  alias System.Validators
  alias Util.Time

  @type t :: %__MODULE__{
          # Formula (39) v0.4.1
          # Hp
          parent_hash: Types.hash(),
          # Formula (43) v0.4.1
          # Hr
          prior_state_root: Types.hash(),
          # Formula (41) v0.4.1
          # Hx
          extrinsic_hash: Types.hash(),
          # Formula (42) v0.4.1
          # Ht
          timeslot: integer(),
          # Formula (45) v0.4.1
          # He
          epoch: {Types.hash(), list(Types.bandersnatch_key())} | nil,
          # Hw
          winning_tickets_marker: list(SealKeyTicket.t()) | nil,
          # Ho
          offenders_marker: list(Types.hash()),
          # Formula (44) v0.4.1
          # Hi
          block_author_key_index: Types.validator_index(),
          # Hv
          vrf_signature: binary(),
          # Hs
          block_seal: binary()
        }

  # Formula (38) v0.4.1
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
  def validate(%__MODULE__{timeslot: current_timeslot} = header, %System.State{} = state) do
    with :ok <- Time.validate_timeslot_order(state.timeslot, current_timeslot),
         :ok <- Time.validate_block_timeslot(current_timeslot),
         :ok <-
           Validators.Safrole.valid_winning_tickets_marker(
             header,
             state.timeslot,
             state.safrole
           ) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Formula (41) v0.4.1
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

  # Formula (303) v0.4.1
  def unsigned_serialize(%Block.Header{} = header) do
    Codec.Encoder.encode({header.parent_hash, header.prior_state_root, header.extrinsic_hash}) <>
      Codec.Encoder.encode_le(header.timeslot, 4) <>
      Codec.Encoder.encode(
        {NilDiscriminator.new(header.epoch), NilDiscriminator.new(header.winning_tickets_marker),
         VariableSize.new(header.offenders_marker),
         Codec.Encoder.encode_le(header.block_author_key_index, 2), header.vrf_signature}
      )
  end

  defimpl Encodable do
    # Formula (302) v0.4.1
    def encode(%Block.Header{} = header) do
      Block.Header.unsigned_serialize(header) <> Codec.Encoder.encode(header.block_seal)
    end
  end

  def from_json(json_data) do
    %__MODULE__{
      parent_hash: Utils.hex_to_binary(json_data[:parent]),
      prior_state_root: Utils.hex_to_binary(json_data[:parent_state_root]),
      extrinsic_hash: Utils.hex_to_binary(json_data[:extrinsic_hash]),
      timeslot: json_data[:slot],
      epoch: parse_epoch_mark(json_data[:epoch_mark]),
      winning_tickets_marker: parse_tickets_mark(json_data[:tickets_mark]),
      offenders_marker: Enum.map(json_data[:offenders_mark] || [], &Utils.hex_to_binary/1),
      block_author_key_index: json_data[:author_index] || 0,
      vrf_signature: Utils.hex_to_binary(json_data[:entropy_source]),
      block_seal: Utils.hex_to_binary(json_data[:seal])
    }
  end

  defp parse_epoch_mark(%{entropy: entropy, validators: validators}) do
    {Utils.hex_to_binary(entropy), Enum.map(validators, &Utils.hex_to_binary/1)}
  end

  defp parse_epoch_mark(_), do: nil

  defp parse_tickets_mark(tickets) when is_list(tickets) do
    Enum.map(tickets, &SealKeyTicket.from_json/1)
  end

  defp parse_tickets_mark(_), do: nil
end
