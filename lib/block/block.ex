defmodule Block do
  alias Block.Extrinsic
  alias Block.Header
  alias Codec.State.Trie
  alias System.{HeaderSeal, State}
  alias System.State.{EntropyPool, RotateKeys, SealKeyTicket}
  alias System.Validators.Safrole
  alias Util.{Hash, Time}
  alias Util.Logger
  use SelectiveMock

  @type t :: %__MODULE__{header: Block.Header.t(), extrinsic: Block.Extrinsic.t()}

  # Formula (4.2) v0.7.2
  defstruct [
    # Hp
    header: nil,
    # Hr
    extrinsic: %Extrinsic{}
  ]

  @spec validate(t(), System.State.t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{header: h, extrinsic: e}, %State{} = s) do
    with :ok <- Header.validate(h, s),
         :ok <- validate_extrinsic_hash(h, e),
         :ok <- validate_refinement_context(h, e),
         :ok <- Extrinsic.validate(e, h, s) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def new(extrinsic, parent_hash, state, timeslot) do
    new(extrinsic, parent_hash, state, timeslot, [])
  end

  def new(extrinsic, parent_hash, state, timeslot, opts) do
    header = %Header{
      timeslot: timeslot,
      prior_state_root: Trie.state_root(state),
      extrinsic_hash: Extrinsic.calculate_hash(extrinsic),
      parent_hash: parent_hash || Hash.zero()
    }

    {pending_, _, _, _} = RotateKeys.rotate_keys(header, state, state.judgements)
    header = put_in(header.epoch_mark, choose_epoch_marker(header.timeslot, state, pending_))

    %{
      slot_sealer: slot_sealer,
      safrole_: safrole_,
      entropy_pool: entropy_pool,
      curr_validators_: curr_validators_
    } =
      get_seal_components(header, state)

    # Get keypair - from opts if provided, otherwise from KeyManager
    keypair =
      if opts[:key_pairs] do
        Enum.find(opts[:key_pairs], &(elem(&1, 1) == slot_sealer))
      else
        KeyManager.get_our_bandersnatch_keypair()
      end

    case keypair do
      nil ->
        {:error, :no_valid_keys_found}

      {priv, pub} ->
        # Check if we own/can sign for this slot
        if key_matches?(keypair, slot_sealer, entropy_pool) do
          block_author_key_index_ =
            Enum.find_index(curr_validators_, fn v -> v.bandersnatch == pub end)

          header = put_in(header.block_author_key_index, block_author_key_index_)
          Logger.debug("timeslot slot_sealer: #{inspect(slot_sealer)}")

          {:ok,
           %__MODULE__{
             header:
               HeaderSeal.seal_header(
                 header,
                 safrole_.slot_sealers,
                 entropy_pool,
                 {priv, pub}
               ),
             extrinsic: extrinsic
           }}
        else
          {:error, :not_our_slot}
        end
    end
  end

  def get_seal_components(header, state) do
    entropy_pool = EntropyPool.rotate(header, state.timeslot, state.entropy_pool)

    {curr_validators_, _, safrole_} =
      System.State.Safrole.transition(
        %Block{header: header, extrinsic: %Extrinsic{}},
        state,
        %System.State.Judgements{},
        entropy_pool
      )

    %{
      slot_sealer: Enum.at(safrole_.slot_sealers, rem(header.timeslot, Constants.epoch_length())),
      safrole_: safrole_,
      entropy_pool: entropy_pool,
      curr_validators_: curr_validators_
    }
  end

  def key_matches?(keypair, %SealKeyTicket{id: id, attempt: r}, pool) do
    context = HeaderSeal.construct_seal_context(%{attempt: r}, pool)
    RingVrf.ietf_vrf_output(keypair, context) == id
  end

  def key_matches?({_priv, pub}, pubkey, _pool) when is_binary(pubkey), do: pub == pubkey

  def choose_epoch_marker(timeslot, state, pending_) do
    if Time.new_epoch?(state.timeslot, timeslot) do
      Safrole.new_epoch_marker(
        state.entropy_pool.n0,
        state.entropy_pool.n1,
        pending_
      )
    else
      nil
    end
  end

  mockable validate_extrinsic_hash(header, extrinsic) do
    if Header.valid_extrinsic_hash?(header, extrinsic) do
      :ok
    else
      {:error, "Invalid extrinsic hash"}
    end
  end

  def mock(:validate_extrinsic_hash, _), do: :ok
  def mock(:validate_refinement_context, _), do: :ok

  import Codec.Encoder
  # Formula (11.35) v0.7.0
  mockable validate_refinement_context(%Header{} = header, %Extrinsic{guarantees: guarantees}) do
    if Jamixir.config()[:ignore_refinement_context] do
      :ok
    else
      Enum.reduce_while(guarantees, :ok, fn g, _ ->
        x = g.work_report.refinement_context

        case Enum.any?(Header.ancestors(header), fn h ->
               h.timeslot == x.timeslot and h(e(h)) == x.lookup_anchor
             end) do
          true -> {:cont, :ok}
          false -> {:halt, {:error, "Refinement context is invalid"}}
        end
      end)
    end
  end

  defimpl Encodable do
    import Codec.Encoder, only: [e: 1]

    # Formula (C.16) v0.7.0
    def encode(%Block{extrinsic: e, header: h}), do: e({h, e})
  end

  def decode(bin) do
    {header, bin} = Header.decode(bin)
    {extrinsic, bin} = Extrinsic.decode(bin)
    {%__MODULE__{header: header, extrinsic: extrinsic}, bin}
  end

  def decode_list(<<>>), do: []

  def decode_list(bin) do
    {block, rest} = decode(bin)
    [block | decode_list(rest)]
  end

  use JsonDecoder
  def json_mapping, do: %{header: Header, extrinsic: Extrinsic}
end
