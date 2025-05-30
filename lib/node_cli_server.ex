defmodule Jamixir.NodeCLIServer do
  alias Network.PeerSupervisor
  alias System.State.Validator
  alias Jamixir.TimeTicker
  use GenServer
  require Logger

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
    RingVrf.init_ring_context()
    {:ok, %{jam_state: init_jam_state(), server_pid: init_network_listener()}}
  end

  defp init_jam_state do
    genesis_file = Application.get_env(:jamixir, :genesis_file, "genesis/genesis.json")
    Logger.info("✨ Initializing JAM state from genesis file: #{genesis_file}")
    {:ok, jam_state} = Codec.State.from_genesis(genesis_file)
    Storage.put(jam_state)
    jam_state
  end

  def init_network_listener do
    port = Application.get_env(:jamixir, :port, 9999)
    {:ok, server_pid} = PeerSupervisor.start_peer(:listener, "::1", port)
    server_pid
  end

  @impl true
  def handle_call({:add_block, block_binary}, _from, _state) do
    case Jamixir.Node.add_block(block_binary) do
      {:ok, _} -> {:reply, :ok, nil}
      {:error, reason} -> {:reply, {:error, reason}, nil}
    end
  end

  @impl true
  def handle_call(:inspect_state, _from, _state) do
    case Jamixir.Node.inspect_state() do
      {:ok, keys} -> {:reply, {:ok, keys}, nil}
      error -> {:reply, error, nil}
    end
  end

  @impl true
  def handle_call({:inspect_state, key}, _from, _state) do
    case Jamixir.Node.inspect_state(key) do
      {:ok, value} -> {:reply, {:ok, value}, nil}
      error -> {:reply, error, nil}
    end
  end

  @impl true
  def handle_call({:load_state, path}, _from, _state) do
    case Jamixir.Node.load_state(path) do
      :ok -> {:reply, :ok, nil}
      error -> {:reply, error, nil}
    end
  end

  @impl true
  def handle_info({:new_timeslot, timeslot}, %{jam_state: jam_state} = state) do
    Logger.debug("Node received new timeslot: #{timeslot}")

    jam_state =
      case Block.new(%Block.Extrinsic{}, nil, jam_state, timeslot) do
        {:ok, block} ->
          Logger.info("⛓️ Block created successfully. #{inspect(block)}")

          case Jamixir.Node.add_block(block) do
            {:ok, new_jam_state} ->
              announce_block_to_peers(new_jam_state.curr_validators)
              new_jam_state

            {:error, reason} ->
              Logger.error("Failed to add block: #{reason}")
              jam_state
          end

        {:error, reason} ->
          Logger.info("Not my turn to create block: #{reason}")
          jam_state
      end

    {:noreply, %{state | jam_state: jam_state}}
  end

  import Util.Hex

  def announce_block_to_peers(validators) do
    Logger.debug("📢 Announcing block to peers")

    for v <- validators do
      case Validator.address(v) do
        nil -> Logger.warning("No address found for this validator: #{encode16(v.bandersnatch)}")
        address -> Logger.debug("📢 Announcing block to peer: #{address}")
      end
    end
  end
end
