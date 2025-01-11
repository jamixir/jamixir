defmodule Network.Client do
  use GenServer
  import Quicer.Flags
  import Network.MessageHandler
  require Logger
  use Codec.Encoder

  @call_default_config [host: ~c"localhost", port: 9999, timeout: 5_000]
  @log_context "[QUIC_CLIENT]"

  @default_stream_opts %{
    active: true
  }

  def log(level, message), do: Logger.log(level, "#{@log_context} #{message}")

  defmodule State do
    defstruct [
      :conn,
      # Map of stream -> {from}
      streams: %{},
      up_streams: %{}
    ]
  end

  def start_link(config \\ [], opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    conf = Keyword.merge(@call_default_config, config)
    GenServer.start_link(__MODULE__, conf, name: name)
  end

  def send(pid, protocol_id, message) when is_integer(protocol_id) do
    GenServer.call(pid, {:send, protocol_id, message}, 5_000)
  end

  def request_blocks(pid, hash, direction, max_blocks) when direction in [0, 1] do
    message = hash <> <<direction::8>> <> <<max_blocks::32>>
    send(pid, 128, message)
  end

  def announce_block(pid, header, slot) do
    log(:debug, "Announcing block at slot #{slot}")
    encoded_header = e(header)
    hash = h(encoded_header)
    messsage = encoded_header <> hash <> <<slot::32>>
    GenServer.cast(pid, {:announce_block, messsage, hash, slot})
  end

  def init(conf) do
    log(:info, "Client connecting...")

    case :quicer.connect(
           conf[:host],
           conf[:port],
           Network.Server.default_opts(),
           conf[:timeout]
         ) do
      {:ok, conn} ->
        log(:info, "Client connected")
        {:ok, %State{conn: conn}}

      error ->
        log(:error, "Client connection failed: #{inspect(error)}")
        {:stop, error}
    end
  end

  def handle_cast(
        {:announce_block, message, hash, slot},
        %{up_streams: up_streams} = state
      ) do
    protocol_id = 0

    {stream, state_} =
      case Map.get(up_streams, protocol_id) do
        # Existing stream - use it without state update
        %{stream_id: stream_id} ->
          log(:debug, "Reusing existing UP stream for block announcement")
          {stream_id, state}

        # No stream - create new one and update state
        nil ->
          log(:info, "Creating new UP stream for block announcements")
          {:ok, stream} = :quicer.start_stream(state.conn, @default_stream_opts)
          state_ = put_in(state.up_streams[protocol_id], %{stream_id: stream})
          {stream, state_}
      end

    log(:debug, "Sending block announcement: hash=#{inspect(hash)}, slot=#{slot}")
    {:ok, _} = :quicer.send(stream, encode_message(protocol_id, message), send_flag(:none))
    {:noreply, state_}
  end

  def handle_call({:send, protocol_id, message}, from, %State{} = state) do
    {:ok, stream} = :quicer.start_stream(state.conn, @default_stream_opts)
    {:ok, _} = :quicer.send(stream, encode_message(protocol_id, message), send_flag(:fin))

    new_state = %State{
      state
      | streams:
          Map.put(state.streams, stream, %{
            from: from
          })
    }

    {:noreply, new_state}
  end

  def handle_info({:quic, data, stream, props}, state) when is_binary(data) do
    handle_stream_data(data, stream, props, state,
      log_tag: "[QUIC_CLIENT]",
      on_complete: fn protocol_id, message, stream ->
        case protocol_id >= 128 and Map.get(state.streams, stream) do
          %{from: from} ->
            response = Network.ClientCalls.call(protocol_id, message)
            GenServer.reply(from, response)

          _ ->
            Task.start(fn -> Network.ClientCalls.call(protocol_id, message) end)
        end
      end
    )
  end

  def handle_info({:quic, :stream_closed, stream, _props}, state) do
    log(:debug, "Stream closed: #{inspect(stream)}")
    {:noreply, %{state | streams: Map.delete(state.streams, stream)}}
  end

  # Catch-all for unhandled QUIC events
  def handle_info({:quic, event_name, _stream, _props} = _msg, state) do
    log(:debug, "Received unhandled event: #{inspect(event_name)}")

    {:noreply, state}
  end

  # Super catch-all for any other messages
  def handle_info(msg, state) do
    log(:debug, "BasicQuicClient received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end
end
