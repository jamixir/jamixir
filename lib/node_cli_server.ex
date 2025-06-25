defmodule Jamixir.NodeCLIServer do
  alias Network.{Connection, ConnectionManager}
  alias Jamixir.TimeTicker
  use GenServer
  alias Util.Logger, as: Log

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def add_block(block_binary), do: GenServer.call(__MODULE__, {:add_block, block_binary})
  def inspect_state, do: GenServer.call(__MODULE__, :inspect_state)
  def inspect_state(key), do: GenServer.call(__MODULE__, {:inspect_state, key})
  def load_state(path), do: GenServer.call(__MODULE__, {:load_state, path})

  @impl true
  def init(_) do
    TimeTicker.subscribe()

    # Get the initialized JAM state from persistent_term (set by InitializationTask)
    jam_state = wait_for_initialization()
    Log.info("🎯 NodeCLIServer initialized with JAM state")

    {:ok, %{jam_state: jam_state}}
  end

  # Wait for initialization to complete and get jam_state
  defp wait_for_initialization do
    case :persistent_term.get(:jam_state, :not_found) do
      :not_found ->
        Log.debug("Waiting for initialization to complete...")
        Process.sleep(100)
        wait_for_initialization()

      jam_state ->
        jam_state
    end
  end

  @impl true
  def handle_call({:add_block, block_binary}, _from, state) do
    case Jamixir.Node.add_block(block_binary) do
      {:ok, _} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:inspect_state, _from, state) do
    case Jamixir.Node.inspect_state() do
      {:ok, :no_state} -> {:reply, {:ok, :no_state}, state}
      {:ok, keys} -> {:reply, {:ok, keys}, state}
    end
  end

  @impl true
  def handle_call({:inspect_state, key}, _from, state) do
    case Jamixir.Node.inspect_state(key) do
      {:ok, value} -> {:reply, {:ok, value}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:load_state, path}, _from, state) do
    case Jamixir.Node.load_state(path) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(
        {:new_timeslot, timeslot},
        %{jam_state: jam_state} = state
      ) do
    Log.debug("Node received new timeslot: #{timeslot}")

    client_pids = ConnectionManager.get_connections()

    jam_state =
      case Block.new(%Block.Extrinsic{}, nil, jam_state, timeslot) do
        {:ok, block} ->
          Log.block(:info, "⛓️ Block created successfully. #{inspect(block)}")

          case Jamixir.Node.add_block(block) do
            {:ok, new_jam_state} ->
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

  def announce_block_to_peers(client_pids, block) do
    Log.debug("📢 Announcing block to #{map_size(client_pids)} peers")

    for {_address, pid} <- client_pids do
      Connection.announce_block(pid, block.header, block.header.timeslot)
    end
  end
end
