defmodule Network.ConnectionSupervisor do
  @moduledoc """
  Supervises Connection processes and acts as the connection registry.
  Prevents duplicate connections and provides connection lookup.
  """

  use GenServer
  alias Util.Logger, as: Log

  defstruct [
    :supervisor_pid,
    # Map: ed25519_key -> pid
    :connections
  ]

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    {:ok, supervisor_pid} = DynamicSupervisor.start_link(strategy: :one_for_one)
    Process.monitor(supervisor_pid)

    {:ok,
     %__MODULE__{
       supervisor_pid: supervisor_pid,
       connections: %{}
     }}
  end

  def start_outbound_connection(remote_ed25519_key, ip, port) do
    GenServer.call(__MODULE__, {:start_outbound_connection, remote_ed25519_key, ip, port})
  end

  def start_inbound_connection(conn, remote_ed25519_key) do
    GenServer.call(__MODULE__, {:start_inbound_connection, conn, remote_ed25519_key})
  end

  def kill_connection(remote_ed25519_key) do
    GenServer.call(__MODULE__, {:kill_connection, remote_ed25519_key})
  end

  def has_connection?(remote_ed25519_key) do
    GenServer.call(__MODULE__, {:has_connection, remote_ed25519_key})
  end

  def get_connection(remote_ed25519_key) do
    GenServer.call(__MODULE__, {:get_connection, remote_ed25519_key})
  end

  def get_all_connections do
    GenServer.call(__MODULE__, :get_all_connections)
  end

  @impl true
  def handle_call({:start_outbound_connection, remote_ed25519_key, ip, port}, _from, state) do
    case Map.get(state.connections, remote_ed25519_key) do
      pid when is_pid(pid) ->
        Log.connection(
          :debug,
          "🔄 Connection already exists, returning existing",
          remote_ed25519_key
        )

        {:reply, {:ok, pid}, state}

      nil ->
        normalized_ip = if is_list(ip), do: ip, else: to_charlist(ip)

        spec = %{
          id: {:outbound_connection, remote_ed25519_key, System.unique_integer()},
          start:
            {Network.Connection, :start_link,
             [
               %{
                 init_mode: :initiator,
                 remote_ed25519_key: remote_ed25519_key,
                 ip: normalized_ip,
                 port: port
               }
             ]},
          restart: :temporary,
          type: :worker
        }

        case DynamicSupervisor.start_child(state.supervisor_pid, spec) do
          {:ok, pid} ->
            Process.monitor(pid)
            new_connections = Map.put(state.connections, remote_ed25519_key, pid)
            Log.connection(:debug, "✅ Started outbound connection", remote_ed25519_key)
            {:reply, {:ok, pid}, %{state | connections: new_connections}}

          error ->
            Log.connection(
              :warning,
              "❌ Failed to start outbound connection: #{inspect(error)}",
              remote_ed25519_key
            )

            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:start_inbound_connection, conn, remote_ed25519_key}, _from, state) do
    case Map.get(state.connections, remote_ed25519_key) do
      pid when is_pid(pid) ->
        Log.connection(
          :debug,
          "🚫 Connection already exists, rejecting duplicate",
          remote_ed25519_key
        )

        :quicer.close_connection(conn)
        {:reply, {:error, :already_exists}, state}

      nil ->
        spec = %{
          id: {:inbound_connection, remote_ed25519_key, System.unique_integer()},
          start:
            {Network.Connection, :start_link,
             [
               %{
                 connection: conn,
                 remote_ed25519_key: remote_ed25519_key
               }
             ]},
          restart: :temporary,
          type: :worker
        }

        case DynamicSupervisor.start_child(state.supervisor_pid, spec) do
          {:ok, pid} ->
            Process.monitor(pid)
            new_connections = Map.put(state.connections, remote_ed25519_key, pid)
            Log.connection(:debug, "✅ Started inbound connection", remote_ed25519_key)
            {:reply, {:ok, pid}, %{state | connections: new_connections}}

          error ->
            Log.connection(
              :warning,
              "❌ Failed to start inbound connection: #{inspect(error)}",
              remote_ed25519_key
            )

            :quicer.close_connection(conn)
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:kill_connection, remote_ed25519_key}, _from, state) do
    case Map.get(state.connections, remote_ed25519_key) do
      pid when is_pid(pid) ->
        Log.connection(:debug, "🔪 Killing dead connection process", remote_ed25519_key)
        DynamicSupervisor.terminate_child(state.supervisor_pid, pid)
        new_connections = Map.delete(state.connections, remote_ed25519_key)
        {:reply, :ok, %{state | connections: new_connections}}

      nil ->
        Log.connection(:debug, "🔍 No process found", remote_ed25519_key)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:has_connection, remote_ed25519_key}, _from, state) do
    has_connection = Map.has_key?(state.connections, remote_ed25519_key)
    {:reply, has_connection, state}
  end

  @impl true
  def handle_call({:get_connection, remote_ed25519_key}, _from, state) do
    case Map.get(state.connections, remote_ed25519_key) do
      pid when is_pid(pid) -> {:reply, {:ok, pid}, state}
      nil -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:get_all_connections, _from, state) do
    {:reply, state.connections, state}
  end

  # Handle process termination - clean up our registry
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove the terminated process from our connections map
    new_connections =
      state.connections
      |> Enum.reject(fn {_key, process_pid} -> process_pid == pid end)
      |> Map.new()

    {:noreply, %{state | connections: new_connections}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end
