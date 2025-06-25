defmodule Network.ConnectionManager do
  @moduledoc """
  Manages all connections lifecycle.
  - initiates connections to validators
  - hadnles incoming connection (from Listener)
  - handles connection status updates (success, lost, disconnected) (from Connection)
  - retries connections

  sits ontop of ConnectionSupervisor to manage connections lifecycle., is the main entry point for all connection related logic.
  no other process touches ConnectionSupervisor directly.
  """

  use GenServer
  alias Network.{ConnectionPolicy, ConnectionSupervisor, ConnectionInfo}
  alias Util.Logger, as: Log

  # 5 seconds before retrying lost connections
  @connection_retry_delay 5000

  defstruct [
    :connections,
    :retry_timers,
    :validators
  ]

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Used by Initialization task when node is started to initiate connections to all validators
  def connect_to_validators(validators) do
    GenServer.call(__MODULE__, {:connect_to_validators, validators})
  end

  # Used by Node CLI server to get all connected client pids in order to announce blocks to them
  def get_connections do
    GenServer.call(__MODULE__, :get_connections)
  end

  # used by Connection to notify us that a connection has been established
  def connection_established(address, pid) do
    GenServer.cast(__MODULE__, {:connection_established, address, pid})
  end

  # used by Connection to notify us that a connection has been lost:
  # kill the connection process(in ConnectionSupervisor) and schedule a retry
  def connection_lost(address) do
    GenServer.cast(__MODULE__, {:connection_lost, address})
  end

  # used by Listener to notify us that a new inbound connection has been established
  def handle_inbound_connection(conn, remote_address, remote_port, local_port) do
    GenServer.cast(
      __MODULE__,
      {:handle_inbound_connection, conn, remote_address, remote_port, local_port}
    )
  end

  ## GenServer Implementation

  @impl GenServer
  def init(_opts) do
    {:ok,
     %__MODULE__{
       connections: %{},
       retry_timers: %{},
       validators: []
     }}
  end

  @impl GenServer
  def handle_call({:connect_to_validators, validators}, _from, state) do
    Log.info("🔗 connecting to #{length(validators)} validators")
    cancel_all_timers(state.retry_timers)

    # Attempt connections to validators
    results = ConnectionPolicy.attempt_connections(validators)

    # Apply actions to update state
    new_state =
      handle_connection_results(results, %{
        state
        | validators: validators,
          retry_timers: %{}
      })

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:get_connections, _from, state) do
    {:reply, ConnectionSupervisor.get_all_connections(), state}
  end

  @impl GenServer
  def handle_cast(
        {:handle_inbound_connection, conn, remote_address, remote_port, local_port},
        state
      ) do
    address = "#{remote_address}:#{remote_port}"
    Log.connection(:info, "📞 Handling inbound connection", address)

    case ConnectionSupervisor.start_inbound_connection(
           conn,
           remote_address,
           remote_port,
           local_port
         ) do
      {:ok, _pid} ->
        Log.connection(:info, "✅ Inbound connection started successfully", address)

        connection_info = %ConnectionInfo{
          status: :connected,
          direction: :inbound,
          target: %{address: address, ip_address: remote_address}
        }

        new_connections = Map.put(state.connections, address, connection_info)
        {:noreply, %{state | connections: new_connections}}

      {:error, :already_exists} ->
        Log.connection(:warning, "🚫 Duplicate inbound connection rejected", address)
        {:noreply, state}

      {:error, reason} ->
        Log.connection(
          :error,
          "❌ Failed to start inbound connection: #{inspect(reason)}",
          address
        )

        :quicer.close_connection(conn)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast({:connection_lost, address}, state) do
    Log.connection(:info, "💔 Connection lost", address)

    case Map.get(state.connections, address) do
      %ConnectionInfo{direction: :outbound} = connection_info ->
        {ip, port} = parse_address(address)
        ConnectionSupervisor.kill_connection(ip, port)

        new_connections =
          Map.put(state.connections, address, %{connection_info | status: :disconnected})

        # Schedule retry for outbound connections
        Log.connection(:info, "📅 Scheduling reconnection attempt (outbound)", address)

        timer_ref =
          Process.send_after(self(), {:retry_connection, address}, @connection_retry_delay)

        new_timers = Map.put(state.retry_timers, address, timer_ref)

        {:noreply,
         %{
           state
           | connections: new_connections,
             retry_timers: new_timers
         }}

      %ConnectionInfo{direction: :inbound} = connection_info ->
        {ip, port} = parse_address(address)
        ConnectionSupervisor.kill_connection(ip, port)

        new_connections =
          Map.put(state.connections, address, %{connection_info | status: :disconnected})

        Log.connection(:info, "👂 Inbound connection lost, waiting for them to reconnect", address)

        {:noreply, %{state | connections: new_connections}}
    end
  end

  @impl GenServer
  def handle_cast({:connection_established, address, pid}, state) do
    Log.connection(:info, "✅ Connection established (PID: #{inspect(pid)})", address)

    existing_conn = Map.get(state.connections, address)

    Log.connection(:debug, "🔄 Updating connection to connected", address)
    updated_conn = %ConnectionInfo{existing_conn | status: :connected}
    updated_connections = Map.put(state.connections, address, updated_conn)

    {:noreply, %{state | connections: updated_connections}}
  end

  @impl GenServer
  def handle_info({:retry_connection, address}, state) do
    Log.connection(:debug, "🔄 Retry timer fired", address)

    connection_info = Map.get(state.connections, address)

    should_initiate = ConnectionPolicy.should_initiate_connection?(connection_info.target)
    has_time = ConnectionPolicy.should_retry?(connection_info.start_time)

    cond do
      should_initiate and has_time ->
        handle_retry_attempt(address, connection_info, state)

      should_initiate ->
        handle_retry_timeout(address, connection_info, state)

      true ->
        handle_retry_wait_inbound(address, connection_info, state)
    end
  end

  ## Private Helper Functions

  defp handle_connection_results(results, state) do
    Enum.reduce(results, state, fn result, acc_state ->
      case result do
        {:connect_success, address, _result, target} ->
          connection_info = %ConnectionInfo{
            status: :connected,
            direction: :outbound,
            target: target
          }

          new_connections = Map.put(acc_state.connections, address, connection_info)
          %{acc_state | connections: new_connections}

        {:connect_failure, address, reason, target} ->
          Log.connection(:warning, "❌ Failed connection: #{inspect(reason)}", address)

          updated_info = %ConnectionInfo{
            status: :retrying,
            retry_count: 1,
            direction: :outbound,
            target: target
          }

          new_connections = Map.put(acc_state.connections, address, updated_info)

          # Schedule retry for failed connection
          delay = ConnectionPolicy.calculate_retry_delay(1)
          timer_ref = Process.send_after(self(), {:retry_connection, address}, delay)
          new_timers = Map.put(acc_state.retry_timers, address, timer_ref)
          Log.connection(:info, "📅 Scheduling retry in #{delay}ms", address)

          %{
            acc_state
            | connections: new_connections,
              retry_timers: new_timers
          }

        {:wait_inbound, address, target} ->
          Log.connection(:info, "👂 Waiting for inbound connection", address)

          connection_info = %ConnectionInfo{
            status: :waiting_inbound,
            direction: :inbound,
            target: target
          }

          %{acc_state | connections: Map.put(acc_state.connections, address, connection_info)}

        {:skip_self, _address, _target} ->
          acc_state
      end
    end)
  end

  defp cancel_all_timers(timers) do
    for {_addr, timer_ref} <- timers do
      Process.cancel_timer(timer_ref)
    end
  end

  defp parse_address(address) do
    parts = String.split(address, ":")
    {port_str, ip_parts} = List.pop_at(parts, -1)
    port = String.to_integer(port_str)
    ip = Enum.join(ip_parts, ":")
    {ip, port}
  end

  # Retry timeout - exceeded max retry duration
  defp handle_retry_timeout(address, connection_info, state) do
    Log.connection(:warning, "⏰ Max retry duration exceeded, giving up", address)

    updated_info = %ConnectionInfo{connection_info | status: :disconnected}
    new_connections = Map.put(state.connections, address, updated_info)

    {:noreply, %{state | connections: new_connections}}
  end

  # Not preferred initiator - wait for them to connect
  defp handle_retry_wait_inbound(address, connection_info, state) do

    updated_info = %ConnectionInfo{
      connection_info
      | status: :waiting_inbound,
        direction: :inbound
    }

    new_connections = Map.put(state.connections, address, updated_info)
    Log.connection(:info, "👂 Waiting for them to connect", address)

    {:noreply, %{state | connections: new_connections}}
  end

  # We should initiate - attempt connection
  defp handle_retry_attempt(address, connection_info, state) do
    Log.connection(:info, "🔄 Attempting retry connection", address)

    case ConnectionPolicy.attempt_connection(connection_info.target) do
      {:ok, _result} ->
        Log.connection(:info, "✅ Retry connection succeeded", address)

        updated_info = %ConnectionInfo{
          connection_info
          | status: :connected,
            direction: :outbound,
            retry_count: 0
        }

        new_connections = Map.put(state.connections, address, updated_info)
        new_timers = Map.delete(state.retry_timers, address)

        {:noreply, %{state | connections: new_connections, retry_timers: new_timers}}

      {:error, reason} ->
        Log.connection(:warning, "❌ Failed retry: #{inspect(reason)}", address)
        retry_count = connection_info.retry_count + 1

        updated_info = %ConnectionInfo{
          connection_info
          | status: :retrying,
            retry_count: retry_count,
            direction: :outbound
        }

        new_connections = Map.put(state.connections, address, updated_info)

        delay = ConnectionPolicy.calculate_retry_delay(retry_count)
        timer_ref = Process.send_after(self(), {:retry_connection, address}, delay)
        new_timers = Map.put(state.retry_timers, address, timer_ref)

        Log.connection(
          :info,
          "📅 Scheduling next retry in #{delay}ms (attempt #{retry_count})",
          address
        )

        {:noreply, %{state | connections: new_connections, retry_timers: new_timers}}
    end
  end
end
