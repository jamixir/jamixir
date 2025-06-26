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

  @type connection_manager_state :: %__MODULE__{
          connections: %{Types.ed25519_key() => ConnectionInfo.t()},
          retry_timers: %{Types.ed25519_key() => reference()},
          validators: list(System.State.Validator.t())
        }

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
    state = %{state | validators: validators, retry_timers: %{}}

    state_ =
      ConnectionPolicy.attempt_connections(validators)
      |> handle_connection_results(state)

    {:reply, :ok, state_}
  end

  @impl GenServer
  def handle_call(:get_connections, _from, state) do
    {:reply, ConnectionSupervisor.get_all_connections(), state}
  end

  @impl GenServer
  def handle_cast(
        {:handle_inbound_connection, conn, ed25519_key},
        state
      ) do
    Log.connection(:info, "📞 Handling inbound connection", ed25519_key)

    case ConnectionSupervisor.start_inbound_connection(conn, ed25519_key) do
      {:ok, _pid} ->
        Log.connection(:info, "✅ Inbound connection started successfully", ed25519_key)

        connection_info = %ConnectionInfo{
          status: :connected,
          direction: :inbound,
          remote_ed25519_key: ed25519_key
        }

        new_connections = Map.put(state.connections, ed25519_key, connection_info)
        {:noreply, %{state | connections: new_connections}}

      {:error, :already_exists} ->
        Log.connection(:warning, "🚫 Duplicate inbound connection rejected", ed25519_key)
        {:noreply, state}

      {:error, reason} ->
        Log.connection(
          :error,
          "❌ Failed to start inbound connection: #{inspect(reason)}",
          ed25519_key
        )

        :quicer.close_connection(conn)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast({:connection_lost, ed25519_key}, state) do
    Log.connection(:info, "💔 Connection lost", ed25519_key)

    case Map.get(state.connections, ed25519_key) do
      %ConnectionInfo{direction: :outbound} = connection_info ->
        ConnectionSupervisor.kill_connection(ed25519_key)

        new_connections =
          Map.put(state.connections, ed25519_key, %{connection_info | status: :disconnected})

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

      %ConnectionInfo{direction: :inbound} = connection_info ->
        ConnectionSupervisor.kill_connection(ed25519_key)

        new_connections =
          Map.put(state.connections, ed25519_key, %{connection_info | status: :disconnected})

        Log.connection(
          :info,
          "👂 Inbound connection lost, waiting for them to reconnect",
          ed25519_key
        )

        {:noreply, %{state | connections: new_connections}}
    end
  end

  @impl GenServer
  def handle_cast({:connection_established, ed25519_key, pid}, state) do
    Log.connection(:info, "✅ Connection established (PID: #{inspect(pid)})", ed25519_key)

    existing_conn = Map.get(state.connections, ed25519_key)

    Log.connection(:debug, "🔄 Updating connection to connected", ed25519_key)
    updated_conn = %ConnectionInfo{existing_conn | status: :connected}
    updated_connections = Map.put(state.connections, ed25519_key, updated_conn)

    {:noreply, %{state | connections: updated_connections}}
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
