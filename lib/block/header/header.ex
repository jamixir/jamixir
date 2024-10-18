defmodule Block.Header do
  alias System.State.Validator
  alias System.State
  alias Util.Merklization
  alias Codec.{NilDiscriminator, VariableSize}
  alias System.State.SealKeyTicket
  alias System.Validators
  alias Util.{Hash, Time}
  use SelectiveMock
  use Codec.Encoder

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
          epoch_mark: {Types.hash(), list(Validator.t())} | nil,
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
    parent_hash: Hash.zero(),
    # Hr
    prior_state_root: nil,
    # Hx
    extrinsic_hash: Hash.zero(),
    # Ht
    timeslot: 0,
    # He
    epoch_mark: nil,
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
         :ok <- validate_state_root(header, state),
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
    header.extrinsic_hash == Util.Hash.default(e(extrinsic))
  end

  # Formula (43) v0.4.1
  mockable validate_state_root(%__MODULE__{prior_state_root: r}, state) do
    if Merklization.merkelize_state(State.serialize(state)) == r,
      do: :ok,
      else: {:error, "Invalid state root"}
  end

  def mock(:validate_state_root, _), do: :ok

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
  def unsigned_encode(%Block.Header{} = header) do
    e({header.parent_hash, header.prior_state_root, header.extrinsic_hash}) <>
      e_le(header.timeslot, 4) <>
      e(
        {NilDiscriminator.new(header.epoch_mark),
         NilDiscriminator.new(header.winning_tickets_marker),
         VariableSize.new(header.offenders_marker), e_le(header.block_author_key_index, 2),
         header.vrf_signature}
      )
  end

  defimpl Encodable do
    use Codec.Encoder
    alias Block.Header
    # Formula (302) v0.4.1
    def encode(%Block.Header{} = header) do
      <<>>
      Header.unsigned_encode(header) <> e(header.block_seal)
    end
  end

  use Sizes
  use Codec.Decoder

  def unsigned_decode(bin) do
    <<parent_hash::binary-size(@hash_size), prior_state_root::binary-size(@hash_size),
      extrinsic_hash::binary-size(@hash_size), timeslot::binary-size(4), bin2::binary>> = bin

    {epoch_mark, bin3} =
      NilDiscriminator.decode(bin2, fn epoch_mark_bin ->
        <<entropy::binary-size(@hash_size), rest::binary>> = epoch_mark_bin

        {keys, cont} =
          Enum.reduce(1..Constants.validator_count(), {[], rest}, fn _, {list, b} ->
            <<key::binary-size(@signature_size), r::binary>> = b
            {list ++ [key], r}
          end)

        {{entropy, keys}, cont}
      end)

    {winning_tickets_marker, bin4} = NilDiscriminator.decode(bin3, & &1)
    {offenders_marker, bin5} = VariableSize.decode(bin4, :hash)

    {%__MODULE__{
       parent_hash: parent_hash,
       prior_state_root: prior_state_root,
       extrinsic_hash: extrinsic_hash,
       timeslot: de_le(timeslot, 4),
       epoch_mark: epoch_mark,
       winning_tickets_marker: winning_tickets_marker,
       offenders_marker: offenders_marker
       # TODO
       # block_author_key_index: e_le(bin5, 2)
       # vrf_signature: vrf_signature,
     }, bin5}
  end

  use JsonDecoder

  def json_mapping do
    %{
      parent_hash: :parent,
      prior_state_root: :parent_state_root,
      timeslot: :slot,
      epoch_mark: [&parse_epoch_mark/1, :epoch_mark],
      winning_tickets_marker: [[SealKeyTicket], :tickets_mark],
      offenders_marker: [:offenders_mark, []],
      block_author_key_index: [:author_index, 0],
      vrf_signature: :entropy_source,
      block_seal: :seal
    }
  end

  defp parse_epoch_mark(%{entropy: entropy, validators: validators}) do
    {JsonDecoder.from_json(entropy), JsonDecoder.from_json(validators)}
  end

  defp parse_epoch_mark(_), do: nil
end
