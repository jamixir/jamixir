defmodule Network.Peer do
  use GenServer
  alias Network.{Client, Server, PeerState}
  require Logger
  import Network.Config
  use Codec.Encoder

  @log_context "[QUIC_PEER]"

  def log(level, message), do: Logger.log(level, "#{@log_context} #{message}")

  # Re-export the client API functions
  defdelegate send(pid, protocol_id, message), to: Client
  defdelegate request_blocks(pid, hash, direction, max_blocks), to: Client
  defdelegate announce_block(pid, header, slot), to: Client
  # Starts the peer handler and connects to a remote peer
  def start_link(config \\ [], opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    conf = Keyword.merge(default_peer_config(), config)
    GenServer.start_link(__MODULE__, {conf[:init_mode], conf[:host], conf[:port]}, name: name)
  end

  @impl GenServer
  def init({:initiator, ip, port}) do
    log(:info, "Initiating connection to #{ip}:#{port}...")

    case :quicer.connect(ip, port, default_quicer_opts(), 5_000) do
      {:ok, conn} ->
        log(:info, "Connected to #{ip}:#{port}")
        {:ok, %PeerState{connection: conn}}

      error ->
        log(:error, "Connection failed: #{inspect(error)}")
        {:stop, error}
    end
  end

  @impl GenServer
  def init({:listener, ip, port}) do
    log(:info, "Listening for connection on #{ip}:#{port}...")

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

  def handle_call({:request_blocks, _, _, _} = msg, from, state),
    do: Client.handle_call(msg, from, state)

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
    if Map.has_key?(state.outgoing_streams, stream) do
      Client.handle_data(data, stream, props, state)
    else
      Server.handle_data(data, stream, props, state)
    end
  end

  # Stream cleanup
  @impl GenServer
  def handle_info({:quic, :stream_closed, stream, _props}, state) do
    log(:info, "Stream closed: #{inspect(stream)}")
    {:noreply, %{state | outgoing_streams: Map.delete(state.outgoing_streams, stream)}}
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
