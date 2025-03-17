defmodule Network.Peer do
  use GenServer
  alias Network.{Client, PeerState, Server}
  require Logger
  import Network.{Config, Codec}

  @log_context "[QUIC_PEER]"

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
  defdelegate announce_verdict(pid, v), to: Client

  # Starts the peer handler and connects to a remote peer
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl GenServer
  def init(%{init_mode: init_mode, ip: ip, port: port}) do
    identifier = "#{init_mode}#{ip}:#{port}"
    {:ok, pid} = Network.PeerRegistry.register_peer(self(), identifier)
    log("Registered peer with identifier: #{identifier} #{inspect(pid)}")

    case init_mode do
      :initiator -> initiate_connection(ip, port)
      :listener -> start_listener(port)
    end
  end

  defp initiate_connection(ip, port) do
    log("Initiating connection to #{ip}:#{port}...")

    case :quicer.connect(ip, port, default_quicer_opts(), 5_000) do
      {:ok, conn} ->
        log("Connected to #{ip}:#{port}")
        {:ok, %PeerState{connection: conn}}

      error ->
        log(:error, "Connection failed: #{inspect(error)}")
        {:stop, error}
    end
  end

  defp start_listener(port) do
    log("Listening for connection on #{port}...")

    case :quicer.listen(port, default_quicer_opts()) do
      {:ok, socket} ->
        send(self(), :accept_connection)
        {:ok, %PeerState{socket: socket}}

      {:error, reason} ->
        log(:error, "Failed to start listener: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  # Client-side handlers
  @impl GenServer
  def handle_call({:send, _, _} = msg, from, state), do: Client.handle_call(msg, from, state)

  @impl GenServer
  def handle_cast({:announce_block, _, _, _} = msg, state), do: Client.handle_cast(msg, state)

  # Server-side handlers
  @impl GenServer
  def handle_info(:accept_connection, state), do: Server.handle_info(:accept_connection, state)
  @impl GenServer
  def handle_info(:accept_stream, state), do: Server.handle_info(:accept_stream, state)

  # Data handling
  @impl GenServer
  def handle_info({:quic, data, stream, props}, state) when is_binary(data) do
    is_response = Map.has_key?(state.pending_responses, stream)

    if is_response do
      protocol_id = Map.get(state.pending_responses, stream).protocol_id
      Client.handle_data(protocol_id, data, stream, props, state)
    else
      protocol_id = get_protocol_id(data)
      Server.handle_data(protocol_id, data, stream, props, state)
    end
  end

  # Stream cleanup
  @impl GenServer
  def handle_info({:quic, :stream_closed, stream, _props}, state) do
    log("Stream closed: #{inspect(stream)}")

    new_state = %{
      state
      | stream_buffers: Map.delete(state.stream_buffers, stream),
        pending_responses: Map.delete(state.pending_responses, stream)
    }

    {:noreply, new_state}
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
    log(:debug, "BasicQuicClient received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end
end
