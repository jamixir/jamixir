defmodule Network.Connection do
  @moduledoc """
  Handles a single bidirectional QUIC connection to a remote peer.
  Each connection is managed by ConnectionManager.
  """

  use GenServer
  alias Network.{Client, ConnectionManager, ConnectionState, Server}
  import Network.Config
  alias Util.Logger, as: Log

  # Get the client module from application config
  defp client_module do
    Application.get_env(:jamixir, :network_client, Network.Client)
  end

  # Re-export the client API functions
  def send(pid, protocol_id, message) do
    client_module().send(pid, protocol_id, message)
  end

  def request_blocks(pid, hash, direction, max_blocks) do
    client_module().request_blocks(pid, hash, direction, max_blocks)
  end

  def announce_block(pid, header, slot) do
    client_module().announce_block(pid, header, slot)
  end

  def announce_preimage(pid, service_id, hash, length) do
    client_module().announce_preimage(pid, service_id, hash, length)
  end

  def get_preimage(pid, hash) do
    client_module().get_preimage(pid, hash)
  end

  def distribute_assurance(pid, assurance) do
    client_module().distribute_assurance(pid, assurance)
  end

  def distribute_ticket(pid, mode, epoch, ticket) do
    client_module().distribute_ticket(pid, mode, epoch, ticket)
  end

  def announce_judgement(pid, epoch, wr_hash, judgement) do
    client_module().announce_judgement(pid, epoch, wr_hash, judgement)
  end

  def distribute_guarantee(pid, guarantee) do
    client_module().distribute_guarantee(pid, guarantee)
  end

  def get_work_report(pid, hash) do
    client_module().get_work_report(pid, hash)
  end

  def send_work_package(pid, wp, core, extrinsics) do
    client_module().send_work_package(pid, wp, core, extrinsics)
  end

  def send_work_package_bundle(pid, bundle, core, segment_roots) do
    client_module().send_work_package_bundle(pid, bundle, core, segment_roots)
  end

  def announce_audit(pid, audit_announcement) do
    client_module().announce_audit(pid, audit_announcement)
  end

  def request_work_report_shard(pid, erasure_root, segment_index) do
    client_module().request_work_report_shard(pid, erasure_root, segment_index)
  end

  def request_audit_shard(pid, erasure_root, segment_index) do
    client_module().request_audit_shard(pid, erasure_root, segment_index)
  end

  def request_state(pid, block_hash, start_key, end_key, max_size) do
    client_module().request_state(pid, block_hash, start_key, end_key, max_size)
  end

  @spec request_segment_shards(pid(), list(SegmentShardsRequest.t()), boolean()) ::
          {:ok, list(binary())} | {:ok, {list(binary()), list(binary())}} | {:error, term()}
  def request_segment_shards(pid, requests, with_justification) do
    client_module().request_segment_shards(pid, requests, with_justification)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  # For outbound connections (initiated by ConnectionManager)
  @impl GenServer
  def init(%{init_mode: :initiator, remote_ed25519_key: remote_ed25519_key, ip: ip, port: port, tls_identity: pkcs12_bundle}) do
    connection_info = %{ip: ip, port: port}

    Log.connection(
      :info,
      "Initiating connection to validator",
      remote_ed25519_key,
      connection_info
    )

    case :quicer.connect(ip, port, quicer_connect_opts(pkcs12_bundle), 10_000) do
      {:ok, conn} ->
        Log.connection(:info, "Connected to validator", remote_ed25519_key, connection_info)

        # Notify ConnectionManager of successful connection
        ConnectionManager.connection_established(remote_ed25519_key, self())

        {:ok,
         %ConnectionState{
           connection: conn,
           remote_ed25519_key: remote_ed25519_key,
           ip: ip,
           port: port
         }}

      error ->
        Log.connection(
          :error,
          "Connection failed: #{inspect(error)}",
          remote_ed25519_key,
          connection_info
        )

        {:stop, error}
    end
  end

  # For incoming connections (pre-established by Listener)
  @impl GenServer
  def init(
        %{
          connection: conn,
          remote_ed25519_key: remote_ed25519_key
        } = args
      ) do
    Log.connection(:info, "Handling incoming connection from validator", remote_ed25519_key)
    # Test-only: register process under an alias if provided
    if pid_alias = args[:test_server_alias] do
      try do
        Process.register(self(), pid_alias)
      rescue
        _ ->
          Log.connection(
            :error,
            "Failed to register process under alias: #{inspect(pid_alias)}",
            remote_ed25519_key
          )
      end
    end

    # Notify ConnectionManager of successful inbound connection
    ConnectionManager.connection_established(remote_ed25519_key, self())

    # Start accepting streams on this connection
    send(self(), :accept_stream)

    {:ok,
     %ConnectionState{
       connection: conn,
       remote_ed25519_key: remote_ed25519_key
     }}
  end

  # Client-side handlers
  @impl GenServer
  def handle_call({:send, _, _} = msg, from, state), do: Client.handle_call(msg, from, state)

  @impl GenServer
  def handle_cast({:announce_block, _, _, _} = msg, state), do: Client.handle_cast(msg, state)

  # Handle graceful shutdown - close QUIC connection properly
  @impl GenServer
  def handle_cast(:shutdown, state) do
    if state.connection && state.connection_closed != true do
      :quicer.close_connection(state.connection)
    end

    {:stop, :shutdown, state}
  end

  # Server-side handlers - only accept streams, connections accepted by Listener are handled by ConnectionManager
  @impl GenServer
  def handle_info(:accept_stream, state), do: Server.handle_info(:accept_stream, state)

  # Handle connection closed - notify ConnectionManager for reconnection logic
  @impl GenServer
  def handle_info({:quic, :closed, _conn_or_stream, _props}, state) do
    if state.connection_closed != true do
      connection_info =
        if state.ip && state.port, do: %{ip: state.ip, port: state.port}, else: nil

      Log.connection(:info, "Connection closed", state.remote_ed25519_key, connection_info)

      # Notify ConnectionManager for potential reconnection
      if state.remote_ed25519_key do
        Log.connection(
          :info,
          "📤 Notifying ConnectionManager of lost connection to validator",
          state.remote_ed25519_key,
          connection_info
        )

        ConnectionManager.connection_lost(state.remote_ed25519_key)
      end

      new_state = %{state | connection_closed: true}
      {:noreply, new_state}
    else
      # Already handled this closure, ignore subsequent events
      {:noreply, state}
    end
  end

  # Data handling
  @impl GenServer
  def handle_info({:quic, data, stream, props}, state) when is_binary(data) do
    is_client_stream = Map.has_key?(state.pending_responses, stream)

    # we expect incoming data for the client only on ce stream resposne.
    # UP streams are used for "cast" i.e. broadcast data one-way, without expecting a response
    if is_client_stream do
      Client.handle_data(data, stream, props, state)
    else
      Server.handle_data(data, stream, props, state)
    end
  end

  # Stream cleanup
  @impl GenServer
  def handle_info({:quic, :stream_closed, stream, _props}, state) do
    Log.connection(:info, "Stream closed: #{inspect(stream)}", state.remote_ed25519_key)
    protocol_id = Map.get(state.up_stream_data, stream, %{}) |> Map.get(:protocol_id)

    new_state = %{
      state
      | pending_responses: Map.delete(state.pending_responses, stream),
        ce_streams: Map.delete(state.ce_streams, stream),
        up_stream_data: Map.delete(state.up_stream_data, stream),
        up_streams: Map.delete(state.up_streams, protocol_id)
    }

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:quic, :new_stream, stream, _props}, state) do
    Log.connection(:info, "Activating new stream: #{inspect(stream)}", state.remote_ed25519_key)

    case :quicer.setopt(stream, :active, true) do
      :ok ->
        Log.connection(
          :info,
          "New stream activated successfully: #{inspect(stream)}",
          state.remote_ed25519_key
        )

      {:error, reason} ->
        Log.connection(
          :error,
          "Failed to activate new stream: #{inspect(stream)} - #{inspect(reason)}",
          state.remote_ed25519_key
        )
    end

    {:noreply, state}
  end

  # Catch-all for unhandled QUIC events
  @impl GenServer
  def handle_info({:quic, event_name, _stream, _props} = _msg, state) do
    Log.connection(
      :debug,
      "Received unhandled event: #{inspect(event_name)}",
      state.remote_ed25519_key
    )

    {:noreply, state}
  end

  # Super catch-all for any other messages
  @impl GenServer
  def handle_info(msg, state) do
    Log.connection(
      :debug,
      "Connection received unknown message: #{inspect(msg)}",
      state.remote_ed25519_key
    )

    {:noreply, state}
  end
end
