defmodule Jamixir.NodeCLIServerBehaviour do
  @callback validator_connections() :: list()
  @callback assigned_shard_index(non_neg_integer(), binary()) :: non_neg_integer() | nil
  @callback assigned_shard_index(binary()) :: non_neg_integer() | nil
end

defmodule Jamixir.NodeCLIServer do
  @behaviour Jamixir.NodeCLIServerBehaviour

  alias Jamixir.Genesis
  alias Jamixir.TimeTicker
  alias Network.{Connection, ConnectionManager}
  alias Util.Logger, as: Log
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def add_block(block_binary), do: GenServer.call(__MODULE__, {:add_block, block_binary})
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

  def set_jam_state(state), do: GenServer.cast(__MODULE__, {:set_jam_state, state})
  def get_jam_state, do: GenServer.call(__MODULE__, :get_jam_state)

  @impl true
  def init(opts) do
    # Try to get JAM state, but don't fail if not available yet
    jam_state = opts[:jam_state] || Storage.get_state(Genesis.genesis_block_parent())

    if jam_state do
      # JAM state is available, proceed normally
      TimeTicker.subscribe()
      Log.info("🎯 NodeCLIServer initialized with JAM state")
      {:ok, %{jam_state: jam_state}}
    else
      # JAM state not available yet, wait for it
      Log.info("⏳ NodeCLIServer waiting for JAM state initialization...")
      TimeTicker.subscribe()
      # Schedule a check for JAM state
      Process.send_after(self(), :check_jam_state, 100)
      {:ok, %{jam_state: nil}}
    end
  end

  # Wait for initialization to complete and get jam_state

  @impl true
  def handle_call({:add_block, block_binary}, _from, state) do
    case Jamixir.Node.add_block(block_binary) do
      {:ok, new_app_state, state_root} -> {:reply, {:ok, new_app_state, state_root}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:validator_connections, _from, %{jam_state: jam_state} = s) do
    {:reply,
     for v <- jam_state.curr_validators do
       {v, ConnectionManager.get_connection(v.ed25519)}
     end, s}
  end

  @impl true
  def handle_call({:validator_index, ed25519_key}, _from, %{jam_state: jam_state} = s) do
    {:reply,
     jam_state.curr_validators
     |> Enum.find_index(fn v -> v.ed25519 == ed25519_key end), s}
  end

  @impl true
  def handle_call(:get_jam_state, _from, %{jam_state: jam_state} = state) do
    {:reply, jam_state, state}
  end

  @impl true
  def handle_cast({:set_jam_state, jam_state}, state) do
    Log.info("Setting JAM state in NodeCLIServer")
    {:noreply, %{state | jam_state: jam_state}}
  end

  @impl true
  def handle_info({:new_timeslot, timeslot}, %{jam_state: jam_state} = state) do
    Log.debug("Node received new timeslot: #{timeslot}")

    client_pids = ConnectionManager.get_connections()

    jam_state =
      case Block.new(%Block.Extrinsic{}, nil, jam_state, timeslot) do
        {:ok, block} ->
          Log.block(:info, "⛓️ Block created successfully. #{inspect(block)}")

          case Jamixir.Node.add_block(block) do
            {:ok, new_jam_state, _state_root} ->
              announce_block_to_peers(client_pids, block)
              new_jam_state

            {:error, reason} ->
              Log.block(:error, "Failed to add block: #{reason}")
              jam_state
          end

        {:error, reason} ->
          Log.consensus(:debug, "Not my turn to create block: #{reason}")
          jam_state
      end

    {:noreply, %{state | jam_state: jam_state}}
  end

  @impl true
  def handle_info(:check_jam_state, %{jam_state: nil} = state) do
    case Storage.get_state(Genesis.genesis_block_parent()) do
      nil ->
        # Still not available, check again later
        Process.send_after(self(), :check_jam_state, 100)
        {:noreply, state}

      jam_state ->
        # JAM state is now available!
        Log.info("🎯 NodeCLIServer received JAM state")
        {:noreply, %{state | jam_state: jam_state}}
    end
  end

  @impl true
  def handle_info(:check_jam_state, state) do
    # Already have JAM state, ignore
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

  def announce_block_to_peers(client_pids, block) do
    Log.debug("📢 Announcing block to #{map_size(client_pids)} peers")

    for {_address, pid} <- client_pids do
      Connection.announce_block(pid, block.header, block.header.timeslot)
    end
  end
end
