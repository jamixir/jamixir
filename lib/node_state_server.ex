defmodule Jamixir.NodeStateServerBehaviour do
  @callback validator_connections() :: list()
  @callback assigned_shard_index(non_neg_integer(), binary()) :: non_neg_integer() | nil
  @callback assigned_shard_index(binary()) :: non_neg_integer() | nil
end

defmodule Jamixir.NodeStateServer do
  @behaviour Jamixir.NodeStateServerBehaviour

  alias System.State.RotateKeys
  alias System.State.EntropyPool
  alias Block.Header
  alias Block.Extrinsic.GuarantorAssignments
  alias Jamixir.Genesis
  alias Network.{Connection, ConnectionManager}
  alias System.State
  alias System.State.SealKeyTicket
  alias Util.Logger, as: Log
  import Util.Hex, only: [b16: 1]
  import Codec.Encoder
  use GenServer

  def instance do
    Application.get_env(:jamixir, :node_state_server, Jamixir.NodeStateServer)
  end

  # Will store {epoch_index, epoch_phase} tuples
  defstruct jam_state: nil, authoring_slots: nil

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def add_block(block, false), do: GenServer.call(__MODULE__, {:add_block, block, false})
  def add_block(block), do: GenServer.call(__MODULE__, {:add_block, block, true})
  def inspect_state(header_hash), do: GenServer.call(__MODULE__, {:inspect_state, header_hash})

  def inspect_state(header_hash, key),
    do: GenServer.call(__MODULE__, {:inspect_state, header_hash, key})

  def load_state(path), do: GenServer.call(__MODULE__, {:load_state, path})
  @impl true
  def validator_connections, do: GenServer.call(__MODULE__, :validator_connections)

  def validator_index(ed25519_key) do
    GenServer.call(__MODULE__, {:validator_index, ed25519_key})
  end

  def validator_index, do: validator_index(KeyManager.get_our_ed25519_key())

  def current_timeslot do
    GenServer.call(__MODULE__, :current_timeslot)
  end

  def guarantors, do: GenServer.call(__MODULE__, :guarantors)

  def assigned_core do
    guarantors = guarantors()

    index =
      Enum.find_index(guarantors.validators, fn v ->
        v.ed25519 == KeyManager.get_our_ed25519_key()
      end)

    if index, do: guarantors.assigned_cores |> Enum.at(index), else: nil
  end

  def same_core_guarantors do
    case assigned_core() do
      nil ->
        []

      core ->
        # we know this is calling twice the guarantors function
        # This can be improved later
        guarantors = guarantors()

        Enum.zip(guarantors.validators, guarantors.assigned_cores)
        |> Enum.filter(fn {v, c} ->
          v.ed25519 != KeyManager.get_our_ed25519_key() and c == core
        end)
        |> Enum.map(fn {v, _c} -> v end)
    end
  end

  def set_jam_state(state), do: GenServer.cast(__MODULE__, {:set_jam_state, state})
  def get_jam_state, do: GenServer.call(__MODULE__, :get_jam_state)

  @impl true
  def init(opts) do
    Process.send_after(self(), {:check_jam_state, opts[:jam_state]}, 0)
    {:ok, %__MODULE__{jam_state: opts[:jam_state]}}
  end

  # Wait for initialization to complete and get jam_state
  @impl true
  def handle_call({:add_block, block, announce}, _from, %__MODULE__{jam_state: jam_state} = state) do
    new_jam_state =
      case Jamixir.Node.add_block(block, jam_state) do
        {:ok, %State{} = new_jam_state, state_root} ->
          Log.info("🔄 State Updated successfully")
          Log.debug("🔄 New State Root: #{b16(state_root)}")
          if announce, do: announce_block_to_peers(block)
          new_jam_state

        {:error, reason} ->
          Log.block(:error, "Failed to add block: #{reason}")
          jam_state
      end

    current_epoch = Util.Time.epoch_index(block.header.timeslot)
    previous_epoch = Util.Time.epoch_index(jam_state.timeslot)

    genServerState =
      if current_epoch - previous_epoch == 1 do
        Log.debug("Recomputing cache: epoch changed from #{previous_epoch} to #{current_epoch}")
        new_authoring_slots = compute_authoring_slots_posterior(new_jam_state)

        %__MODULE__{
          state
          | jam_state: new_jam_state,
            authoring_slots: new_authoring_slots
        }
      else
        %__MODULE__{state | jam_state: new_jam_state}
      end

    {:reply, {:ok, new_jam_state}, genServerState}
  end

  @impl true
  def handle_call(:validator_connections, _from, %__MODULE__{jam_state: jam_state} = s) do
    {:reply,
     for v <- jam_state.curr_validators do
       {v, ConnectionManager.get_connection(v.ed25519)}
     end, s}
  end

  @impl true
  def handle_call({:validator_index, ed25519_key}, _from, %__MODULE__{jam_state: jam_state} = s) do
    {:reply,
     jam_state.curr_validators
     |> Enum.find_index(fn v -> v.ed25519 == ed25519_key end), s}
  end

  @impl true
  def handle_call(:current_timeslot, _from, %__MODULE__{jam_state: jam_state} = state) do
    {:reply, jam_state.timeslot, state}
  end

  @impl true
  def handle_call(:guarantors, _from, %__MODULE__{jam_state: jam_state} = state) do
    guarantors =
      GuarantorAssignments.guarantors(
        jam_state.entropy_pool.n2,
        jam_state.timeslot,
        jam_state.curr_validators,
        MapSet.new()
      )

    {:reply, guarantors, state}
  end

  @impl true
  def handle_call(:get_jam_state, _from, %__MODULE__{jam_state: jam_state} = state) do
    {:reply, jam_state, state}
  end

  @impl true
  def handle_cast({:set_jam_state, jam_state}, state) do
    Log.info("Setting JAM state in NodeStateServer")
    {:noreply, %{state | jam_state: jam_state}}
  end

  @impl true
  def handle_info({:check_jam_state, s}, %__MODULE__{jam_state: nil} = state) do
    case s || Storage.get_state(Genesis.genesis_header_hash()) do
      nil ->
        # Still not available, check again later
        Process.send_after(self(), {:check_jam_state, nil}, 100)
        {:noreply, state}

      jam_state ->
        # JAM state is now available!
        Log.info("🎯 NodeStateServer received JAM state")
        Phoenix.PubSub.subscribe(Jamixir.PubSub, "clock_events")
        {:noreply, %__MODULE__{state | jam_state: jam_state}}
    end
  end

  @impl true
  # Already have JAM state, ignore
  def handle_info({:check_jam_state, _}, state), do: {:noreply, state}

  @impl true
  def handle_info(
        {:clock_event, %{event: :slot_tick, slot: slot}},
        %__MODULE__{jam_state: jam_state, authoring_slots: nil} = state
      ) do
    Log.debug("Node received new timeslot: #{slot}")

    {_, parent_header} = Storage.get_latest_header()
    parent_hash = h(e(parent_header))

    header = %Header{timeslot: slot}
    entropy_pool_ = EntropyPool.rotate(slot, jam_state.timeslot, jam_state.entropy_pool)

    {_pending_, curr_validators_, _prev_validators_, _epoch_root_} =
      RotateKeys.rotate_keys(header, jam_state, %System.State.Judgements{})

      next_slot_sealers =
        System.State.Safrole.get_epoch_slot_sealers_(
          header,
          jam_state.timeslot,
          jam_state.safrole,
          entropy_pool_,
          curr_validators_
        )

    case Block.new(%Block.Extrinsic{}, parent_hash, jam_state, slot) do
      {:ok, block} ->
        header_hash = h(e(block.header))
        Log.block(:info, "⛓️ Block created successfully. Header Hash #{b16(header_hash)}")
        Log.block(:debug, "⛓️ Block created successfully. #{inspect(block)}")
        Task.start(fn -> add_block(block) end)

      {:error, reason} ->
        Log.consensus(:debug, "Not my turn to create block: #{reason}")
    end

    {:noreply, state}
  end

  # Handle other clock events (ignore for now)
  @impl true
  def handle_info({:clock_event, _event}, state) do
    {:noreply, state}
  end

  @impl true
  # i = (cR + v) mod V
  def assigned_shard_index(core, key \\ KeyManager.get_our_ed25519_key()) do
    case validator_index(key) do
      nil ->
        nil

      v ->
        rem(core * Constants.erasure_code_recovery_threshold() + v, Constants.validator_count())
    end
  end

  defp announce_block_to_peers(block) do
    client_pids = ConnectionManager.get_connections()
    Log.debug("📢 Announcing block to #{map_size(client_pids)} peers")

    for {_address, pid} <- client_pids do
      Connection.announce_block(pid, block.header, block.header.timeslot)
    end
  end

  # For add_block handler - already has posterior state
  defp compute_authoring_slots_posterior(jam_state) do
    epoch_ = Util.Time.epoch_index(jam_state.timeslot)
    bandersnatch_keypair = KeyManager.get_our_bandersnatch_keypair()

    Log.debug("🎯 Computing authoring slots for next epoch #{epoch_} (posterior)")

    # Use the existing posterior state directly
    authoring_slots =
      0..(Constants.epoch_length() - 1)
      |> Enum.filter(
        &our_turn_to_author?(&1, jam_state.safrole, bandersnatch_keypair, jam_state.entropy_pool)
      )
      |> Enum.map(fn phase -> {epoch_, phase} end)
      |> MapSet.new()

    Log.info("🎯 We are assigned to author #{inspect(authoring_slots)} slots in epoch #{epoch_}")

    authoring_slots
  end

  defp our_turn_to_author?(epoch_phase, safrole, bandersnatch_keypair, entropy_pool) do
    # Use the passed safrole (which should be for the correct epoch)
    slot_sealer = Enum.at(safrole.slot_sealers, epoch_phase)
    {_priv, pubkey} = bandersnatch_keypair

    case slot_sealer do
      # Fallback key case - direct bandersnatch key comparison
      bandersnatch_key when is_binary(bandersnatch_key) ->
        pubkey == bandersnatch_key

      # Seal ticket case - use Ring VRF to check if we can sign
      %SealKeyTicket{} = ticket ->
        can_sign_ticket?(ticket, entropy_pool, bandersnatch_keypair)

      _ ->
        false
    end
  end

  defp can_sign_ticket?(ticket, entropy_pool, bandersnatch_keypair) do
    # Construct the seal context for this ticket using the same logic as Block.get_signing_key
    context =
      System.HeaderSeal.construct_seal_context(
        %{attempt: ticket.attempt},
        %System.State.EntropyPool{n3: entropy_pool.n3}
      )

    RingVrf.ietf_vrf_output(bandersnatch_keypair, context) == ticket.id
  end

  # Helper function to check if cache is stale
  defp cache_is_stale_for_current_epoch?(authoring_slots, current_slot) do
    if authoring_slots == nil do
      # nil is not stale, it's just not populated
      false
    else
      current_epoch = Util.Time.epoch_index(current_slot)

      # Check if any cached slot is for the current epoch
      authoring_slots
      |> Enum.any?(fn {epoch_index, _phase} -> epoch_index == current_epoch end)
      # Stale if NO slots are for current epoch
      |> Kernel.not()
    end
  end
end
