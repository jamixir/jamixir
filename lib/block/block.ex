defmodule Block do
  alias Util.Hash
  alias System.State.RotateKeys
  alias Block.Extrinsic
  alias Block.Header
  alias Codec.State.Trie
  alias System.HeaderSeal
  alias System.State
  alias System.State.EntropyPool
  alias System.State.SealKeyTicket
  alias System.Validators.Safrole
  alias Util.Time
  require Logger
  use SelectiveMock

  @type t :: %__MODULE__{header: Block.Header.t(), extrinsic: Block.Extrinsic.t()}

  # Formula (4.2) v0.6.6
  defstruct [
    # Hp
    header: nil,
    # Hr
    extrinsic: nil
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

    params = get_seal_components(header, state)

    case get_signing_key(opts[:key_pairs], params.pubkey, params.entropy_pool, params.safrole_) do
      {:ok, keypair} ->
        {_, pubkey} = keypair

        new_index =
          Enum.find_index(params.curr_validators_, fn v -> v.bandersnatch == pubkey end)

        header = put_in(header.block_author_key_index, new_index)
        Logger.debug("timeslot pubkey: #{inspect(params.pubkey)}")

        {:ok,
         %__MODULE__{
           header:
             HeaderSeal.seal_header(
               header,
               params.safrole_.slot_sealers,
               params.entropy_pool,
               keypair
             ),
           extrinsic: extrinsic
         }}

      {:error, e} ->
        {:error, e}
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
      pubkey: Enum.at(safrole_.slot_sealers, rem(header.timeslot, Constants.epoch_length())),
      safrole_: safrole_,
      entropy_pool: entropy_pool,
      curr_validators_: curr_validators_
    }
  end

  defp get_signing_key(nil, %SealKeyTicket{id: id, attempt: r}, pool, _) do
    case my_key() do
      {{priv, pub}, pub} ->
        # my_index = Enum.find_index(safrole_.pending, fn v -> v.bandersnatch == pub end)
        context = HeaderSeal.construct_seal_context(%{attempt: r}, %EntropyPool{n3: pool.n3})

        case RingVrf.ietf_vrf_output({priv, pub}, context) do
          ^id -> {:ok, {{priv, pub}, pub}}
          _ -> {:error, :no_valid_keys_found}
        end

      # output =
      #   RingVrf.ring_vrf_output(
      #     for(v <- safrole_.pending, do: v.bandersnatch),
      #     {priv, pub},
      #     my_index,
      #     HeaderSeal.construct_seal_context(ticket, pool)
      #   )

      # output_hash = RingVrf.ring_vrf_output(public_keys, keypair, 0, context)

      # if output == id do
      # {:ok, {{priv, pub}, pub}}

      # else
      # end

      _ ->
        {:error, :no_valid_keys_found}
    end
  end

  defp get_signing_key(nil, pubkey, _, _) do
    case my_key() do
      {{priv, ^pubkey}, ^pubkey} ->
        {:ok, {{priv, pubkey}, pubkey}}

      _ ->
        {:error, :no_valid_keys_found}
    end
  end

  defp get_signing_key(key_pairs, pubkey, _, _) do
    case Enum.find(key_pairs, &(elem(&1, 1) == pubkey)) do
      nil -> {:error, :key_not_found}
      priv -> {:ok, priv}
    end
  end

  def my_key do
    case Application.get_env(:jamixir, :keys) do
      %{bandersnatch_priv: priv, bandersnatch: pubkey} -> {{priv, pubkey}, pubkey}
      _ -> nil
    end
  end

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
  # Formula (11.35) v0.6.6
  mockable validate_refinement_context(%Header{} = header, %Extrinsic{guarantees: guarantees}) do
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

  defimpl Encodable do
    import Codec.Encoder, only: [e: 1]

    # Formula (C.13) v0.6.6
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
