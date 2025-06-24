defmodule Network.Connection do
  @moduledoc """
  Handles a single bidirectional QUIC connection to a remote peer.
  Each connection is managed by ConnectionManager.
  """

  use GenServer
  alias Network.{Client, PeerState, Server, ConnectionManager}
  require Logger
  import Network.Config
  import Utils, only: [format_ip_address: 1]

  @log_context "[CONNECTION]"

  def log(level, message), do: Logger.log(level, "#{@log_context} #{message}")
  def log(message), do: Logger.info("#{@log_context} #{message}")

  # Re-export the client API functions
  defdelegate send(pid, protocol_id, message), to: Client
  defdelegate request_blocks(pid, hash, direction, max_blocks), to: Client
  defdelegate announce_block(pid, header, slot), to: Client
  defdelegate announce_preimage(pid, service_id, hash, length), to: Client
  defdelegate get_preimage(pid, hash), to: Client
  defdelegate distribute_assurance(pid, assurance), to: Client
  defdelegate distribute_ticket(pid, mode, epoch, ticket), to: Client
  defdelegate announce_judgement(pid, epoch, wr_hash, judgement), to: Client
  defdelegate distribute_guarantee(pid, guarantee), to: Client
  defdelegate get_work_report(pid, hash), to: Client
  defdelegate send_work_package(pid, wp, core, extrinsics), to: Client
  defdelegate send_work_package_bundle(pid, bundle, core, segment_roots), to: Client
  defdelegate announce_audit(pid, audit_announcement), to: Client
  defdelegate request_segment(pid, erasure_root, segment_index), to: Client
  defdelegate request_audit_shard(pid, erasure_root, segment_index), to: Client
  defdelegate request_state(pid, block_hash, start_key, end_key, max_size), to: Client
  defdelegate request_segment_shards(pid, requests, with_justification), to: Client

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  # For outbound connections (initiated by ConnectionManager)
  @impl GenServer
  def init(%{init_mode: :initiator, ip: ip, port: port}) do
    remote_address = format_ip_address(ip)
    log("Initiating connection to #{remote_address}:#{port}...")

    case :quicer.connect(ip, port, default_quicer_opts(), 10_000) do
      {:ok, conn} ->
        log("Connected to #{remote_address}:#{port}")

        # Notify ConnectionManager of successful connection
        address = "#{remote_address}:#{port}"
        ConnectionManager.connection_established(address, self())

        {:ok, %PeerState{connection: conn, remote_address: remote_address, remote_port: port}}

      error ->
        log(:error, "Connection failed: #{inspect(error)}")
        {:stop, error}
    end
  end

  # For incoming connections (pre-established by Listener)
  @impl GenServer
  def init(%{
        connection: conn,
        remote_address: remote_address,
        remote_port: remote_port,
        local_port: local_port
      }) do
    log(
      "Handling incoming connection from #{remote_address}:#{remote_port} (connecting to our port #{local_port})"
    )

    # Start accepting streams on this connection
    send(self(), :accept_stream)

    {:ok,
     %PeerState{
       connection: conn,
       remote_address: remote_address,
       remote_port: remote_port,
       local_port: local_port
     }}
  end

  # Helper function to get remote address for supervisor registry
  @impl GenServer
  def handle_call(:get_remote_address, _from, state) do
    {:reply, {state.remote_address, state.remote_port}, state}
  end

  # Client-side handlers
  @impl GenServer
  def handle_call({:send, _, _} = msg, from, state), do: Client.handle_call(msg, from, state)

  @impl GenServer
  def handle_cast({:announce_block, _, _, _} = msg, state), do: Client.handle_cast(msg, state)

  # Server-side handlers - only accept streams, connections accepted by Listener are handled by ConnectionManager
  @impl GenServer
  def handle_info(:accept_stream, state), do: Server.handle_info(:accept_stream, state)

  # Handle connection closed - notify ConnectionManager for reconnection logic
  @impl GenServer
  def handle_info({:quic, :closed, _conn_or_stream, _props}, state) do
    if state.connection_closed != true do
      log("Connection closed")

      # Notify ConnectionManager for potential reconnection (only if outbound)
      if state.remote_address && state.remote_port do
        address = "#{state.remote_address}:#{state.remote_port}"
        log("📤 Notifying ConnectionManager of lost connection to #{address}")
        ConnectionManager.connection_lost(address)
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
    log("Stream closed: #{inspect(stream)}")

    new_state = %{
      state
      | pending_responses: Map.delete(state.pending_responses, stream),
        ce_streams: Map.delete(state.ce_streams, stream),
        up_stream_data: Map.delete(state.up_stream_data, stream)
    }

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:quic, :new_stream, stream, _props}, state) do
    log("Activating new stream: #{inspect(stream)}")

    case :quicer.setopt(stream, :active, true) do
      :ok ->
        log("New stream activated successfully: #{inspect(stream)}")

      {:error, reason} ->
        log("Failed to activate new stream: #{inspect(stream)} - #{inspect(reason)}")
    end

    {:noreply, state}
  end

  # Catch-all for unhandled QUIC events
  @impl GenServer
  def handle_info({:quic, event_name, _stream, _props} = _msg, state) do
    log(:debug, "Received unhandled event: #{inspect(event_name)}")
    {:noreply, state}
  end

  # Super catch-all for any other messages
  @impl GenServer
  def handle_info(msg, state) do
    log(:debug, "Connection received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end
end
