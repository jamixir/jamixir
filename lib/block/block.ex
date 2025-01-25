defmodule Block do
  alias Block.Extrinsic
  alias Block.Header
  alias System.HeaderSeal
  alias System.State
  alias System.State.EntropyPool
  alias System.Validators.Safrole
  alias Util.Merklization
  alias Util.Time
  use SelectiveMock

  @type t :: %__MODULE__{header: Block.Header.t(), extrinsic: Block.Extrinsic.t()}

  # Formula (13) v0.4.5
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

  def new(extrinsic, parent_hash, state, timeslot, key_pairs: key_pairs) do
    header = %Header{
      timeslot: timeslot,
      prior_state_root: Merklization.merkelize_state(State.serialize(state)),
      extrinsic_hash: Extrinsic.calculate_hash(extrinsic),
      parent_hash: parent_hash
    }

    header = put_in(header.epoch_mark, choose_epoch_marker(timeslot, state))
    rotated_entropy_pool = EntropyPool.rotate(header, state.timeslot, state.entropy_pool)

    {_, _, safrole_} =
      System.State.Safrole.transition(
        %Block{header: header, extrinsic: %Extrinsic{}},
        state,
        %System.State.Judgements{},
        rotated_entropy_pool
      )

    pubkey =
      Enum.at(safrole_.slot_sealers, rem(timeslot, Constants.epoch_length()))

    new_index = Enum.find_index(state.curr_validators, fn v -> v.bandersnatch == pubkey end)

    header = put_in(header.block_author_key_index, new_index)

    with key <- Enum.find(key_pairs, &(elem(&1, 1) == pubkey)),
         %{ed25519_priv: key, ed25519: pub} <-
           if(key == nil,
             do: Application.get_env(:jamixir, :keys),
             else: %{ed25519: pubkey, ed25519_priv: key}
           ),
         :ok <- if(pubkey != pub, do: :error, else: :ok) do
      #  my_key <- if(key1 == nil, do: key, else: key1) do
      {:ok,
       %__MODULE__{
         header:
           HeaderSeal.seal_header(
             header,
             safrole_.slot_sealers,
             rotated_entropy_pool,
             key
           ),
         extrinsic: extrinsic
       }}
    else
      true -> {:error, :author_key_not_found}
    end
  end

  defp choose_epoch_marker(timeslot, state) do
    if Time.new_epoch?(state.timeslot, timeslot) do
      Safrole.new_epoch_marker(
        state.entropy_pool.n0,
        state.entropy_pool.n1,
        state.safrole.pending
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

  use Codec.Encoder
  # Formula (149) v0.4.5
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
    use Codec.Encoder

    # Formula (C.13) v0.5.0
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
