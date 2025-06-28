defmodule Network.ConnectionManager do
  @moduledoc """
  Central orchestrator for all network connections.

  - Directly supervises all connection processes (inbound and outbound)
  - Handles connection lifecycle: creation, monitoring, retry, and shutdown
  - All connection creation, lookup, and shutdown is handled via this module

  Entry points:
  - connect_to_validators/1: Initiate connections to all validators
  - start_outbound_connection/3: Start a single outbound connection
  - handle_inbound_connection/2: Handle a new inbound connection
  - get_connection/1, get_connections/0: Lookup connection PIDs
  - shutdown_all_connections/0: Graceful shutdown of all connections

  """

  use GenServer
  alias Network.{ConnectionPolicy, ConnectionInfo}
  alias Util.Logger, as: Log

  @type connection_manager_state :: %__MODULE__{
          supervisor_pid: pid(),
          connections: %{Types.ed25519_key() => ConnectionInfo.t()},
          retry_timers: %{Types.ed25519_key() => reference()},
          validators: list(System.State.Validator.t())
        }

  # 5 seconds before retrying lost connections
  @connection_retry_delay 5000

  defstruct [
    :supervisor_pid,
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

  def get_connection(ed25519_key) do
    GenServer.call(__MODULE__, {:get_connection, ed25519_key})
  end

  # used by Connection to notify us that a connection has been established
  def connection_established(ed25519_key, pid) do
    GenServer.cast(__MODULE__, {:connection_established, ed25519_key, pid})
  end

  # used by Connection to notify us that a connection has been lost:
  # kill the connection process(in ConnectionSupervisor) and schedule a retry
  def connection_lost(ed25519_key) do
    GenServer.cast(__MODULE__, {:connection_lost, ed25519_key})
  end

  # used by Listener to notify us that a new inbound connection has been established
  def handle_inbound_connection(conn, ed25519_key) do
    GenServer.cast(__MODULE__, {:handle_inbound_connection, conn, ed25519_key})
  end

  # Internal function used by ConnectionPolicy to start outbound connections
  def start_outbound_connection(remote_ed25519_key, ip, port) do
    GenServer.call(__MODULE__, {:start_outbound_connection, remote_ed25519_key, ip, port})
  end

  def shutdown_all_connections do
    GenServer.cast(__MODULE__, :shutdown_all_connections)
  end

  def kill_all_incoming do
    GenServer.cast(__MODULE__, :kill_all_incoming)
  end

  ## GenServer Implementation

  @impl GenServer
  def init(_opts) do
    {:ok, supervisor_pid} = DynamicSupervisor.start_link(strategy: :one_for_one)
    Process.monitor(supervisor_pid)

    {:ok,
     %__MODULE__{
       supervisor_pid: supervisor_pid,
       connections: %{},
       retry_timers: %{},
       validators: []
     }}
  end

  @impl GenServer
  def handle_call({:connect_to_validators, validators}, _from, state) do
    Log.info("🔗 connecting to #{length(validators)} validators")
    cancel_all_timers(state.retry_timers)
    state = %{state | validators: validators, retry_timers: %{}}

    state_ =
      ConnectionPolicy.attempt_connections(validators)
      |> handle_connection_results(state)

    {:reply, :ok, state_}
  end

  @impl GenServer
  def handle_call(:get_connections, _from, state) do
    # Extract PIDs from our connections state
    connection_pids =
      state.connections
      |> Enum.filter(fn {_key, conn_info} -> conn_info.pid != nil end)
      |> Enum.into(%{}, fn {key, conn_info} -> {key, conn_info.pid} end)

    {:reply, connection_pids, state}
  end

  @impl GenServer
  def handle_call({:get_connection, ed25519_key}, _from, state) do
    case Map.get(state.connections, ed25519_key) do
      %ConnectionInfo{pid: pid} when is_pid(pid) ->
        {:reply, {:ok, pid}, state}

      %ConnectionInfo{pid: nil} ->
        {:reply, {:error, :not_connected}, state}

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:start_outbound_connection, remote_ed25519_key, ip, port}, _from, state) do
    # Check if connection already exists
    case Map.get(state.connections, remote_ed25519_key) do
      %ConnectionInfo{pid: pid} when is_pid(pid) ->
        Log.connection(
          :debug,
          "🔄 Connection already exists, returning existing",
          remote_ed25519_key
        )

        {:reply, {:ok, pid}, state}

      _no_active_connection ->
        # Create DynamicSupervisor spec for outbound connection
        spec = %{
          id: {:outbound_connection, remote_ed25519_key, System.unique_integer()},
          start:
            {Network.Connection, :start_link,
             [
               %{
                 init_mode: :initiator,
                 remote_ed25519_key: remote_ed25519_key,
                 ip: ip,
                 port: port
               }
             ]},
          restart: :temporary,
          type: :worker
        }

        case DynamicSupervisor.start_child(state.supervisor_pid, spec) do
          {:ok, pid} ->
            Process.monitor(pid)
            Log.connection(:debug, "✅ Started outbound connection", remote_ed25519_key)

            connection_info = %ConnectionInfo{
              status: :connecting,
              direction: :outbound,
              remote_ed25519_key: remote_ed25519_key,
              pid: pid
            }

            new_connections = Map.put(state.connections, remote_ed25519_key, connection_info)
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

  @impl GenServer
  def handle_cast(
        {:handle_inbound_connection, conn, ed25519_key},
        state
      ) do
    Log.connection(:info, "📞 Handling inbound connection", ed25519_key)

    # Check if connection already exists
    case Map.get(state.connections, ed25519_key) do
      %ConnectionInfo{pid: pid} when is_pid(pid) ->
        Log.connection(
          :debug,
          "🚫 Connection already exists, rejecting duplicate",
          ed25519_key
        )

        :quicer.close_connection(conn)
        {:noreply, state}

      _no_active_connection ->
        # Create DynamicSupervisor spec for inbound connection
        spec = %{
          id: {:inbound_connection, ed25519_key, System.unique_integer()},
          start:
            {Network.Connection, :start_link,
             [
               %{
                 connection: conn,
                 remote_ed25519_key: ed25519_key
               }
             ]},
          restart: :temporary,
          type: :worker
        }

        case DynamicSupervisor.start_child(state.supervisor_pid, spec) do
          {:ok, pid} ->
            # Transfer ownership after the process is started
            case :quicer.controlling_process(conn, pid) do
              :ok ->
                Process.monitor(pid)
                Log.connection(:info, "✅ Inbound connection started successfully", ed25519_key)

                connection_info = %ConnectionInfo{
                  status: :connected,
                  direction: :inbound,
                  remote_ed25519_key: ed25519_key,
                  pid: pid
                }

                new_connections = Map.put(state.connections, ed25519_key, connection_info)
                {:noreply, %{state | connections: new_connections}}

              {:error, reason} ->
                Log.connection(
                  :warning,
                  "❌ Failed to transfer connection ownership: #{inspect(reason)}",
                  ed25519_key
                )

                # Clean up the process we just started
                DynamicSupervisor.terminate_child(state.supervisor_pid, pid)
                :quicer.close_connection(conn)
                {:noreply, state}
            end

          error ->
            Log.connection(
              :error,
              "❌ Failed to start inbound connection: #{inspect(error)}",
              ed25519_key
            )

            :quicer.close_connection(conn)
            {:noreply, state}
        end
    end
  end

  @impl GenServer
  def handle_cast({:connection_lost, ed25519_key}, state) do
    Log.connection(:info, "💔 Connection lost", ed25519_key)

    case Map.get(state.connections, ed25519_key) do
      %ConnectionInfo{direction: :outbound, pid: pid} = connection_info ->
        # Kill the connection process if it exists
        if is_pid(pid) do
          Log.connection(:debug, "🔪 Killing dead connection process", ed25519_key)
          DynamicSupervisor.terminate_child(state.supervisor_pid, pid)
        end

        new_connections =
          Map.put(state.connections, ed25519_key, %{
            connection_info
            | status: :disconnected,
              pid: nil
          })

        # Schedule retry for outbound connections
        Log.connection(:info, "📅 Scheduling reconnection attempt (outbound)", ed25519_key)

        timer_ref =
          Process.send_after(self(), {:retry_connection, ed25519_key}, @connection_retry_delay)

        new_timers = Map.put(state.retry_timers, ed25519_key, timer_ref)

        {:noreply,
         %{
           state
           | connections: new_connections,
             retry_timers: new_timers
         }}

      %ConnectionInfo{direction: :inbound, pid: pid} = connection_info ->
        # Kill the connection process if it exists
        if is_pid(pid) do
          Log.connection(:debug, "🔪 Killing dead connection process", ed25519_key)
          DynamicSupervisor.terminate_child(state.supervisor_pid, pid)
        end

        new_connections =
          Map.put(state.connections, ed25519_key, %{
            connection_info
            | status: :disconnected,
              pid: nil
          })

        Log.connection(
          :info,
          "👂 Inbound connection lost, waiting for them to reconnect",
          ed25519_key
        )

        {:noreply, %{state | connections: new_connections}}

      nil ->
        # Connection not tracked in our state, ignore
        Log.connection(
          :debug,
          "🚫 Received connection_lost for unknown connection, ignoring",
          ed25519_key
        )

        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast({:connection_established, ed25519_key, pid}, state) do
    Log.connection(:info, "✅ Connection established (PID: #{inspect(pid)})", ed25519_key)

    existing_conn = Map.get(state.connections, ed25519_key)

    case existing_conn do
      %ConnectionInfo{} = conn_info ->
        Log.connection(:debug, "🔄 Updating existing connection to connected", ed25519_key)
        updated_conn = %ConnectionInfo{conn_info | status: :connected, pid: pid}
        updated_connections = Map.put(state.connections, ed25519_key, updated_conn)
        {:noreply, %{state | connections: updated_connections}}

      nil ->
        # Connection not tracked, create a new entry (probably from test or external connection)
        Log.connection(
          :debug,
          "🆕 Creating new connection entry for unknown connection",
          ed25519_key
        )

        new_conn = %ConnectionInfo{
          status: :connected,
          # Assume inbound since we didn't initiate it
          direction: :inbound,
          remote_ed25519_key: ed25519_key,
          start_time: System.monotonic_time(:millisecond),
          retry_count: 0,
          pid: pid
        }

        updated_connections = Map.put(state.connections, ed25519_key, new_conn)
        {:noreply, %{state | connections: updated_connections}}
    end
  end

  @impl GenServer
  def handle_cast(:shutdown_all_connections, state) do
    IO.puts("🛑 Shutting down all connections gracefully")

    for {ed25519_key, %ConnectionInfo{pid: pid}} <- state.connections do
      if is_pid(pid) && Process.alive?(pid) do
        Log.connection(:debug, "🛑 Shutting down connection", ed25519_key)
        GenServer.cast(pid, :shutdown)
      end
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:kill_all_incoming, state) do
    for {ed25519_key, %ConnectionInfo{direction: :inbound, pid: pid}} <- state.connections do
      if is_pid(pid) and Process.alive?(pid) do
        Log.connection(:info, "Killing inbound connection", ed25519_key)
        GenServer.stop(pid, :normal)
      end
    end

    new_connections =
      state.connections
      |> Enum.map(fn
        {key, %ConnectionInfo{direction: :inbound} = info} ->
          {key, %{info | pid: nil, status: :disconnected}}

        pair ->
          pair
      end)
      |> Map.new()

    {:noreply, %{state | connections: new_connections}}
  end

  @impl GenServer
  def handle_info({:retry_connection, ed25519_key}, state) do
    Log.connection(:debug, "🔄 Retry timer fired", ed25519_key)

    connection_info = Map.get(state.connections, ed25519_key)

    should_initiate = ConnectionPolicy.should_initiate_connection?(ed25519_key)
    has_time = ConnectionPolicy.should_retry?(connection_info.start_time)

    cond do
      should_initiate and has_time ->
        handle_retry_attempt(ed25519_key, connection_info, state)

      should_initiate ->
        handle_retry_timeout(ed25519_key, connection_info, state)

      true ->
        handle_retry_wait_inbound(ed25519_key, connection_info, state)
    end
  end

  # Handle process termination - clean up our connections map
  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Find and update the connection info that had this PID
    new_connections =
      state.connections
      |> Enum.map(fn {key, conn_info} ->
        if conn_info.pid == pid do
          {key, %{conn_info | pid: nil, status: :disconnected}}
        else
          {key, conn_info}
        end
      end)
      |> Map.new()

    {:noreply, %{state | connections: new_connections}}
  end

  ## Private Helper Functions

  @spec handle_connection_results(
          list(ConnectionPolicy.connection_attempt_result()),
          connection_manager_state()
        ) :: connection_manager_state()
  defp handle_connection_results(results, state) do
    Enum.reduce(results, state, fn result, acc_state ->
      case result do
        {:connect_success, ed25519_key} ->
          connection_info = %ConnectionInfo{
            status: :connected,
            direction: :outbound,
            remote_ed25519_key: ed25519_key
          }

          new_connections = Map.put(acc_state.connections, ed25519_key, connection_info)
          %{acc_state | connections: new_connections}

        {:connect_failure, ed25519_key} ->
          updated_info = %ConnectionInfo{
            status: :retrying,
            retry_count: 1,
            direction: :outbound,
            remote_ed25519_key: ed25519_key
          }

          new_connections = Map.put(acc_state.connections, ed25519_key, updated_info)

          # Schedule retry for failed connection
          delay = ConnectionPolicy.calculate_retry_delay(1)
          timer_ref = Process.send_after(self(), {:retry_connection, ed25519_key}, delay)
          new_timers = Map.put(acc_state.retry_timers, ed25519_key, timer_ref)
          Log.connection(:info, "📅 Scheduling retry in #{delay}ms", ed25519_key)

          %{
            acc_state
            | connections: new_connections,
              retry_timers: new_timers
          }

        {:wait_inbound, ed25519_key} ->
          Log.connection(:info, "👂 Waiting for inbound connection", ed25519_key)

          connection_info = %ConnectionInfo{
            status: :waiting_inbound,
            direction: :inbound,
            remote_ed25519_key: ed25519_key
          }

          %{acc_state | connections: Map.put(acc_state.connections, ed25519_key, connection_info)}

        {:skip_self, _ed25519_key} ->
          acc_state
      end
    end)
  end

  defp cancel_all_timers(timers) do
    for {_addr, timer_ref} <- timers do
      Process.cancel_timer(timer_ref)
    end
  end

  # Retry timeout - exceeded max retry duration
  defp handle_retry_timeout(ed25519_key, connection_info, state) do
    Log.connection(:warning, "⏰ Max retry duration exceeded, giving up", ed25519_key)

    updated_info = %ConnectionInfo{connection_info | status: :disconnected}
    new_connections = Map.put(state.connections, ed25519_key, updated_info)

    {:noreply, %{state | connections: new_connections}}
  end

  # Not preferred initiator - wait for them to connect
  defp handle_retry_wait_inbound(ed25519_key, connection_info, state) do
    updated_info = %ConnectionInfo{
      connection_info
      | status: :waiting_inbound,
        direction: :inbound
    }

    new_connections = Map.put(state.connections, ed25519_key, updated_info)
    Log.connection(:info, "👂 Waiting for them to connect", ed25519_key)

    {:noreply, %{state | connections: new_connections}}
  end

  # We should initiate - attempt connection
  defp handle_retry_attempt(ed25519_key, connection_info, state) do
    Log.connection(:info, "🔄 Attempting retry connection", ed25519_key)

    # Find the validator by ed25519_key
    case find_validator_by_ed25519_key(ed25519_key) do
      nil ->
        Log.connection(:warning, "❌ Validator not found for retry", ed25519_key)
        {:noreply, state}

      validator ->
        case ConnectionPolicy.attempt_connection(validator) do
          {:ok, _result} ->
            Log.connection(:info, "✅ Retry connection succeeded", ed25519_key)

            updated_info = %ConnectionInfo{
              connection_info
              | status: :connected,
                direction: :outbound,
                retry_count: 0
            }

            new_connections = Map.put(state.connections, ed25519_key, updated_info)
            new_timers = Map.delete(state.retry_timers, ed25519_key)

            {:noreply, %{state | connections: new_connections, retry_timers: new_timers}}

          {:error, reason} ->
            Log.connection(:warning, "❌ Failed retry: #{inspect(reason)}", ed25519_key)
            retry_count = connection_info.retry_count + 1

            updated_info = %ConnectionInfo{
              connection_info
              | status: :retrying,
                retry_count: retry_count,
                direction: :outbound
            }

            new_connections = Map.put(state.connections, ed25519_key, updated_info)

            delay = ConnectionPolicy.calculate_retry_delay(retry_count)
            timer_ref = Process.send_after(self(), {:retry_connection, ed25519_key}, delay)
            new_timers = Map.put(state.retry_timers, ed25519_key, timer_ref)

            Log.connection(
              :info,
              "📅 Scheduling next retry in #{delay}ms (attempt #{retry_count})",
              ed25519_key
            )

            {:noreply, %{state | connections: new_connections, retry_timers: new_timers}}
        end
    end
  end

  # Helper to find validator by ed25519_key from current state
  defp find_validator_by_ed25519_key(ed25519_key) do
    case :persistent_term.get(:jam_state, nil) do
      nil ->
        nil

      jam_state ->
        Enum.find(jam_state.curr_validators, fn validator ->
          validator.ed25519 == ed25519_key
        end)
    end
  end
end
