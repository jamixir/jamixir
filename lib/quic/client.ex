defmodule Quic.Client do
  use GenServer
  import Quic.Flags
  require Logger

  @call_default_config [host: ~c"localhost", port: 9999, timeout: 5_000]
  @log_context "[QUIC_CLIENT]"

  def log(level, message), do: Logger.log(level, "#{@log_context} #{message}")

  defmodule State do
    defstruct [
      :conn,
      # Map of stream -> {from, timer_ref}
      streams: %{}
    ]
  end

  def start_link(config \\ []) do
    conf = Keyword.merge(@call_default_config, config)
    GenServer.start_link(__MODULE__, conf, name: __MODULE__)
  end

  def send(pid, protocol_id, message) when is_integer(protocol_id) do
    GenServer.call(pid, {:send, protocol_id, message}, 5_000)
  end

  def request_blocks(pid, hash, direction, max_blocks) when direction in [0, 1] do
    message = hash <> <<direction::8>> <> <<max_blocks::32>>
    send(pid, 128, message)
  end

  def init(conf) do
    log(:info, "Client connecting...")

    case :quicer.connect(
           conf[:host],
           conf[:port],
           Quic.Server.default_opts(),
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

  def handle_call({:send, protocol_id, message}, from, %State{} = state) do
    stream_opts = %{
      active: true,
      # QUICER_STREAM_EVENT_MASK_START_COMPLETE
      quic_event_mask: 0x00000001,
      open_flag: stream_open_flag(:none)
    }

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
    log(:info, "Stream start completed: #{inspect(props)}")

    case Map.get(state.streams, stream) do
      %{message: message, protocol_id: protocol_id} ->
        encoded = Quic.MessageHandler.encode_message(protocol_id, message)
        {:ok, _} = :quicer.send(stream, encoded, send_flag(:fin))
        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:quic, data, stream, props}, %State{streams: streams} = state)
      when is_binary(data) do
    Quic.MessageHandler.handle_stream_data(
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

  # def handle_info({:quic, :peer_send_aborted, stream, error_code}, %State{} = state) do
  #   Logger.debug("#{@log_context} Stream #{inspect(stream)} peer send aborted")
  #   Logger.info("#{@log_context} Stream #{inspect(stream)} peer send aborted")

  #   case Map.get(state.streams, stream) do
  #     nil ->
  #       {:noreply, state}

  #     %{from: from, timer_ref: timer_ref} ->
  #       Process.cancel_timer(timer_ref)
  #       GenServer.reply(from, {:error, {:aborted, error_code}})
  #       new_state = %State{state | streams: Map.delete(state.streams, stream)}
  #       {:noreply, new_state}
  #   end
  # end

  # Catch-all for unhandled QUIC events
  def handle_info({:quic, event_name, _resource, _props} = msg, state) do
    log(:debug, "BasicQuicClient received unhandled QUIC event: #{inspect(event_name)}")

    {:noreply, state}
  end

  # Super catch-all for any other messages
  def handle_info(msg, state) do
    log(:debug, "BasicQuicClient received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end
end
