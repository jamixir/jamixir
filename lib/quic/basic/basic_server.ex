defmodule BasicQuicServer do
  use GenServer
  alias System.Network.CertUtils
  require Logger

  @log_context "[QUIC_SERVER]"

  def log(level, message), do: Logger.log(level, "#{@log_context} #{message}")

  defmodule State do
    defstruct [
      :socket,
      :connection,
      # Track messages per stream
      streams: %{}
    ]
  end

  @fixed_opts [
    alpn: [~c"jamnp-s/V/H"],
    peer_bidi_stream_count: 100,
    peer_unidi_stream_count: 100,
    versions: [:"tlsv1.3"],
    verify: :none
  ]

  @default_opts [
                  certfile: ~c"#{CertUtils.certfile()}",
                  keyfile: ~c"#{CertUtils.keyfile()}"
                ] ++ @fixed_opts

  def start_link(port \\ 9999) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  def init(port) do
    log(:info, "Starting on port #{port}")
    {:ok, socket} = :quicer.listen(port, @default_opts)
    send(self(), :accept_connection)
    {:ok, %State{socket: socket}}
  end

  def handle_info(:accept_connection, %{socket: socket} = state) do
    case :quicer.accept(socket, [], :infinity) do
      {:ok, conn} ->
        log(:info, "Connection accepted")
        {:ok, conn} = :quicer.handshake(conn)
        log(:info, "Handshake completed")
        send(self(), :accept_stream)
        {:noreply, %{state | connection: conn}}

      error ->
        log(:error, "Accept error: #{inspect(error)}")
        send(self(), :accept_connection)
        {:noreply, state}
    end
  end

  def handle_info(:accept_stream, %{connection: conn} = state) do
    case :quicer.accept_stream(conn, [{:active, true}], :infinity) do
      {:ok, stream} ->
        log(:debug, "Stream accepted: #{inspect(stream)}")
        send(self(), :accept_stream)
        {:noreply, state}

      error ->
        log(:error, "Stream accept error: #{inspect(error)}")
        {:noreply, state}
    end
  end

  def handle_info({:quic, data, stream, %{flags: flags} = props}, state) when is_binary(data) do
    log(:debug, "Props: #{inspect(props)}")
    log(:debug, "Data: #{inspect(data)}")

    buffer = Map.get(state.streams, stream, <<>>)
    new_buffer = buffer <> data
    log(:debug, "new_buffer: #{inspect(new_buffer)}")

    case process_message(new_buffer) do
      {:complete, message, _stream_id} ->
        {:ok, _} = :quicer.send(stream, message)
        log(:debug, "sent}")
        {:noreply, %{state | streams: Map.delete(state.streams, stream)}}

      {:incomplete, partial_buffer} ->
        # Keep buffering until we have the complete message
        log(:debug, "Incomplete message, keep buffering")
        {:noreply, %{state | streams: Map.put(state.streams, stream, partial_buffer)}}
    end
  end

  def handle_info({:quic, :stream_closed, stream, _props}, state) do
    {:noreply, %{state | streams: Map.delete(state.streams, stream)}}
  end

  # handler for :peer_send_shutdown
  def handle_info({:quic, :peer_send_shutdown, stream, _props}, state) do
    {:noreply, %{state | streams: Map.delete(state.streams, stream)}}
  end

  defp process_message(buffer) do
    if byte_size(buffer) >= 5 do
      <<stream_id::8, length::32-little, rest::binary>> = buffer

      if byte_size(rest) >= length do
        <<message::binary-size(length), _::binary>> = rest
        {:complete, message, stream_id}
      else
        {:incomplete, buffer}
      end
    else
      {:incomplete, buffer}
    end
  end
end
