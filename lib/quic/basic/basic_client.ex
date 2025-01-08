defmodule BasicQuicClient do
  use GenServer
  import Quic.Basic.Flags
  require Logger

  @call_default_config [host: ~c"localhost", port: 9999, timeout: 5_000]
  @log_context "[QUIC_CLIENT]"

  def log(level, message), do: Logger.log(level, "#{@log_context} #{message}")

  defmodule State do
    @initial_stream_id 128
    defstruct [
      :conn,
      next_stream_id: @initial_stream_id,
      # Map of stream -> {from, timer_ref}
      streams: %{}
    ]
  end

  def start_link(config \\ []) do
    conf = Keyword.merge(@call_default_config, config)
    GenServer.start_link(__MODULE__, conf, name: __MODULE__)
  end

  def send_and_wait(pid, message) do
    GenServer.call(pid, {:send_and_wait, message}, 5_000)
  end

  def init(conf) do
    log(:info, "Client connecting...")

    case :quicer.connect(
           conf[:host],
           conf[:port],
           QuicServer.default_opts(),
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

  def handle_call({:send_and_wait, message}, from, %State{} = state) do
    stream_id = state.next_stream_id
    log(:debug, "Starting stream with ID: #{stream_id}")

    stream_opts = %{
      active: 10000,
      stream_id: stream_id,
      start_flag: stream_start_flag(:indicate_peer_accept),
      # QUICER_STREAM_EVENT_MASK_START_COMPLETE
      quic_event_mask: 0x00000001,
      open_flag: stream_open_flag(:none)
    }

    {:ok, stream} =
      :quicer.start_stream(state.conn, stream_opts)

    timer_ref = Process.send_after(self(), {:stream_timeout, stream}, 5_000)

    new_state = %State{
      state
      | next_stream_id: stream_id + 4,
        streams:
          Map.put(state.streams, stream, %{from: from, timer_ref: timer_ref, message: message})
    }

    {:noreply, new_state}
  end

  def handle_info(
        {:quic, :start_completed, stream,
         %{status: :success, is_peer_accepted: true, stream_id: stream_id} = props},
        state
      ) do
    log(:debug, "Stream start completed: #{inspect(props)}")
    log(:info, "Stream start completed: #{inspect(props)}")

    case Map.get(state.streams, stream) do
      %{message: message} ->
        length = byte_size(message)
        {:ok, _} = :quicer.send(stream, <<stream_id::8>>, send_flag(:none))
        # {:ok, _} = :quicer.send(stream, <<length::32-little>>, send_flag(:none))
        {:ok, _} = :quicer.send(stream, <<length::32-little>> <> message, send_flag(:fin))
        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:quic, :start_completed, _stream, %{status: status} = props}, state) do
    log(
      :debug,
      "Stream start completed with status: #{inspect(status)}, props: #{inspect(props)}"
    )

    log(:info, "Stream start completed with status: #{inspect(status)}, props: #{inspect(props)}")

    {:noreply, state}
  end

  def handle_info({:quic, data, stream, _props}, %State{streams: streams} = state)
      when is_binary(data) do
    log(:info, "Data received on stream: #{inspect(stream)}")

    case Map.get(streams, stream) do
      nil ->
        {:noreply, state}

      %{from: from, timer_ref: timer_ref} ->
        Process.cancel_timer(timer_ref)
        GenServer.reply(from, {:ok, {:ok, data}})
        new_state = %State{state | streams: Map.delete(state.streams, stream)}
        {:noreply, new_state}
    end
  end

  def handle_info({:quic, :stream_closed, stream, _props}, %State{} = state) do
    log(:info, "Stream closed: #{inspect(stream)}")

    case Map.get(state.streams, stream) do
      nil ->
        {:noreply, state}

      %{from: from, timer_ref: timer_ref} ->
        Process.cancel_timer(timer_ref)
        # GenServer.reply(from, :ok)
        if Process.alive?(from), do: GenServer.reply(from, :ok)

        new_state = %State{state | streams: Map.delete(state.streams, stream)}
        {:noreply, new_state}
    end
  end

  def handle_info({:stream_timeout, stream}, %State{} = state) do
    log(:info, "Stream timeout: #{inspect(stream)}")

    case Map.get(state.streams, stream) do
      nil ->
        {:noreply, state}

      %{from: from} ->
        GenServer.reply(from, {:error, :timeout})
        new_state = %State{state | streams: Map.delete(state.streams, stream)}
        {:noreply, new_state}
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
