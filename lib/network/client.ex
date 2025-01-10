defmodule Network.Client do
  use GenServer
  import Quicer.Flags
  import Network.MessageHandler
  require Logger
  use Codec.Encoder

  @call_default_config [host: ~c"localhost", port: 9999, timeout: 5_000]
  @log_context "[QUIC_CLIENT]"

  @default_stream_opts %{
    active: true,
    # QUICER_STREAM_EVENT_MASK_START_COMPLETE
    quic_event_mask: 0x00000001
  }

  def log(level, message), do: Logger.log(level, "#{@log_context} #{message}")

  defmodule State do
    defstruct [
      :conn,
      # Map of stream -> {from, timer_ref}
      streams: %{},
      up_stream: nil
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
        GenServer.cast(self(), :init_up_stream)
        {:ok, %State{conn: conn}}

      error ->
        log(:error, "Client connection failed: #{inspect(error)}")
        {:stop, error}
    end
  end

  def handle_cast(:init_up_stream, %{conn: conn} = state) do
    case start_up_stream(conn, 0) do
      {:ok, up_stream} ->
        log(:info, "UP stream initialized")
        {:noreply, %{state | up_stream: up_stream}}

      {:error, error} ->
        log(:error, "Failed to initialize UP stream: #{inspect(error)}")
        {:noreply, state}
    end
  end

  def handle_cast(
        {:announce_block, message, hash, slot},
        %{up_stream: stream} = state
      ) do
    case :quicer.send(stream, encode_message(0, message), send_flag(:none)) do
      {:ok, _} ->
        log(:debug, "Block announced: hash=#{inspect(hash)}, slot=#{slot}")

      error ->
        log(:error, "Failed to announce block: #{inspect(error)}")
    end

    {:noreply, state}
  end

  def handle_call({:send, protocol_id, message}, from, %State{} = state) do
    stream_opts = @default_stream_opts

    {:ok, stream} = :quicer.start_stream(state.conn, stream_opts)
    timer_ref = Process.send_after(self(), {:stream_timeout, stream}, 5_000)

    new_state = %State{
      state
      | streams:
          Map.put(state.streams, stream, %{
            from: from,
            timer_ref: timer_ref,
            protocol_id: protocol_id,
            message: message
          })
    }

    {:noreply, new_state}
  end

  def handle_info(
        {:quic, :start_completed, stream, %{status: :success, is_peer_accepted: true} = props},
        state
      ) do
    log(:debug, "Stream start completed: #{inspect(props)}")

    case Map.get(state.streams, stream) do
      %{message: message, protocol_id: protocol_id} ->
        {:ok, _} = :quicer.send(stream, encode_message(protocol_id, message), send_flag(:fin))
        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:quic, data, stream, props}, %State{streams: streams} = state)
      when is_binary(data) do
    handle_stream_data(
      data,
      stream,
      props,
      state,
      log_tag: "[QUIC_CLIENT]",
      on_complete: fn protocol_id, message, stream ->
        case Map.get(streams, stream) do
          %{from: from, timer_ref: timer_ref} ->
            Process.cancel_timer(timer_ref)

            response =
              case protocol_id do
                128 -> {:ok, Block.decode_list(message)}
                _ -> {:ok, message}
              end

            GenServer.reply(from, response)
            {:noreply, %{state | streams: Map.delete(state.streams, stream)}}

          nil ->
            {:noreply, state}
        end
      end
    )
  end

  def handle_info({:quic, :stream_closed, stream, _props}, state) do
    log(:debug, "Stream closed: #{inspect(stream)}")
    {:noreply, %{state | streams: Map.delete(state.streams, stream)}}
  end

  def handle_info({:quic, :peer_send_shutdown, stream, _props}, state) do
    log(:debug, "Peer send shutdown for stream: #{inspect(stream)}")
    {:noreply, state}
  end

  def handle_info({:quic, :send_shutdown_complete, stream, _props}, state) do
    log(:debug, "Send shutdown complete for stream: #{inspect(stream)}")
    {:noreply, state}
  end

  def handle_info({:stream_timeout, stream}, %State{} = state) do
    log(:info, "Stream timeout: #{inspect(stream)}")

    case Map.get(state.streams, stream) do
      nil ->
        {:noreply, state}

      %{from: from} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, state}
    end
  end

  # Catch-all for unhandled QUIC events
  def handle_info({:quic, event_name, _resource, _props} = _msg, state) do
    log(:debug, "BasicQuicClient received unhandled QUIC event: #{inspect(event_name)}")

    {:noreply, state}
  end

  # Super catch-all for any other messages
  def handle_info(msg, state) do
    log(:debug, "BasicQuicClient received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp start_up_stream(conn, protocol_id) do
    stream_opts = @default_stream_opts

    with {:ok, stream} <- :quicer.start_stream(conn, stream_opts),
         {:ok, _} <- :quicer.send(stream, <<protocol_id::8>>, send_flag(:none)) do
      {:ok, stream}
    end
  end
end
