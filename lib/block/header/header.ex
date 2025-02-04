defmodule Block.Header do
  alias Block.Extrinsic
  alias Block.Header
  alias Codec.{NilDiscriminator, State.Trie, VariableSize}
  alias System.Validators
  alias System.State.{SealKeyTicket, Validator}
  alias Util.{Hash, Time}
  use SelectiveMock

  use Codec.Encoder
  import Codec.Decoder

  @type t :: %__MODULE__{
          # Formula (5.2) v0.6.0
          # Hp
          parent_hash: Types.hash(),
          # Formula (5.8) v0.6.0
          # Hr
          prior_state_root: Types.hash(),
          # Formula (5.4) v0.6.0
          # Hx
          extrinsic_hash: Types.hash(),
          # Formula (5.7) v0.6.0
          # Ht
          timeslot: integer(),
          # Formula (5.10) v0.6.0
          # He
          epoch_mark: {Types.hash(), Types.hash(), list(Validator.t())} | nil,
          # Hw
          winning_tickets_marker: list(SealKeyTicket.t()) | nil,
          # Ho
          offenders_marker: list(Types.hash()),
          # Formula (5.9) v0.6.0
          # Hi
          block_author_key_index: Types.validator_index(),
          # Hv
          vrf_signature: binary(),
          # Hs
          block_seal: binary()
        }

  # Formula (5.1) v0.6.0
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
    vrf_signature: nil,
    # Hs
    block_seal: <<>>
  ]

  @spec validate(t(), System.State.t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{timeslot: current_timeslot} = header, %System.State{} = state) do
    with :ok <- Time.validate_timeslot_order(state.timeslot, current_timeslot),
         :ok <- Time.validate_block_timeslot(current_timeslot),
         :ok <- validate_parent(header),
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

  # Formula (5.4) v0.6.0
  def valid_extrinsic_hash?(header, extrinsic),
    do: header.extrinsic_hash == Extrinsic.calculate_hash(extrinsic)

  # Formula (5.8) v0.6.0
  mockable validate_state_root(%__MODULE__{prior_state_root: r}, state) do
    state_root = Trie.state_root(state)

    if state_root == r,
      do: :ok,
      else:
        {:error,
         "Invalid state root. \nHeader: #{Base.encode16(r)}, \nState: #{Base.encode16(state_root)}"}
  end

  use MapUnion

  # Formula (5.3) v0.6.0
  # h ∈ A ⇔ h = H ∨ (∃i ∈ A ∶ h = P (i))
  def ancestors(nil), do: []

  def ancestors(%__MODULE__{} = h) do
    Stream.unfold(h, fn
      nil -> nil
      %__MODULE__{parent_hash: nil} = current -> {current, nil}
      %__MODULE__{parent_hash: ph} = current -> {current, Storage.get(ph)}
    end)
  end

  def mock(:validate_state_root, _), do: :ok
  def mock(:validate_parent, _), do: :ok

  mockable validate_parent(header) do
    if header.parent_hash == nil do
      :ok
    else
      case Storage.get(header.parent_hash) do
        nil ->
          {:error, :no_parent}

        parent_header ->
          if parent_header.timeslot < header.timeslot do
            :ok
          else
            {:error, :invalid_parent_timeslot}
          end
      end
    end
  end

  # Formula (C.20) v0.6.0
  def unsigned_encode(%Block.Header{} = header) do
    e({header.parent_hash, header.prior_state_root, header.extrinsic_hash}) <>
      e_le(header.timeslot, 4) <>
      e({
        NilDiscriminator.new(header.epoch_mark),
        NilDiscriminator.new(header.winning_tickets_marker),
        vs(header.offenders_marker),
        e_le(header.block_author_key_index, 2),
        header.vrf_signature
      })
  end

  defimpl Encodable do
    use Codec.Encoder
    alias Block.Header
    # Formula (C.19) v0.6.0
    def encode(%Block.Header{} = header) do
      <<>>
      Header.unsigned_encode(header) <> e(header.block_seal)
    end
  end

  use Sizes
  use Codec.Decoder

  def unsigned_decode(bin) do
    <<parent_hash::binary-size(@hash_size), prior_state_root::binary-size(@hash_size),
      extrinsic_hash::binary-size(@hash_size), timeslot::32-little, bin::binary>> = bin

    {epoch_mark, bin} =
      NilDiscriminator.decode(bin, fn epoch_mark_bin ->
        <<entropy::binary-size(@hash_size), tickets_entropy::binary-size(@hash_size),
          rest::binary>> = epoch_mark_bin

        {keys, cont} = decode_list(rest, :hash, Constants.validator_count())

        {{entropy, tickets_entropy, keys}, cont}
      end)

    {winning_tickets_marker, bin} =
      NilDiscriminator.decode(
        bin,
        &decode_list(&1, Constants.epoch_length(), SealKeyTicket)
      )

    {offenders_marker, bin} = VariableSize.decode(bin, :hash)
    <<block_author_key_index::16-little, bin::binary>> = bin
    <<vrf_signature::binary-size(96), rest::binary>> = bin

    {%__MODULE__{
       parent_hash: parent_hash,
       prior_state_root: prior_state_root,
       extrinsic_hash: extrinsic_hash,
       timeslot: timeslot,
       epoch_mark: epoch_mark,
       winning_tickets_marker: winning_tickets_marker,
       offenders_marker: offenders_marker,
       block_author_key_index: block_author_key_index,
       vrf_signature: vrf_signature,
       block_seal: nil
     }, rest}
  end

  def decode(bin) do
    {header, bin} = unsigned_decode(bin)
    <<block_seal::binary-size(96), rest::binary>> = bin
    {%__MODULE__{header | block_seal: block_seal}, rest}
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

  defp parse_epoch_mark(%{
         entropy: entropy,
         tickets_entropy: tickets_entropy,
         validators: validators
       }) do
    {
      JsonDecoder.from_json(entropy),
      JsonDecoder.from_json(tickets_entropy),
      JsonDecoder.from_json(validators)
    }
  end

  defp parse_epoch_mark(_), do: nil
end
