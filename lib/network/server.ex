defmodule Network.Server do
  use GenServer
  alias Network.CertUtils
  require Logger
  alias Quicer.Flags
  import Network.MessageHandler

  @log_context "[QUIC_SERVER]"

  def log(level, message), do: Logger.log(level, "#{@log_context} #{message}")

  defmodule State do
    defstruct [
      :socket,
      :connection,
      streams: %{},
      up_streams: %{}
    ]
  end

  @fixed_opts [
    alpn: [~c"jamnp-s/V/H"],
    peer_bidi_stream_count: 1023,
    peer_unidi_stream_count: 100,
    versions: [:"tlsv1.3"],
    verify: :none
  ]

  @default_opts [
                  certfile: ~c"#{CertUtils.certfile()}",
                  keyfile: ~c"#{CertUtils.keyfile()}"
                ] ++ @fixed_opts

  def default_opts, do: @default_opts

  def start_link(port, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, port, name: name)
  end

  def init(port) do
    log(:info, "Starting on port #{port}")
    case :quicer.listen(port, @default_opts) do
      {:ok, socket} ->
        send(self(), :accept_connection)
        {:ok, %State{socket: socket}}

      {:error, :listener_start_error, _reason} = error ->
        {:stop, error}

      error ->
        {:stop, error}
    end
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
    case :quicer.accept_stream(conn, [{:active, true}], 0) do
      {:ok, stream} ->
        log(:debug, "Stream accepted: #{inspect(stream)}")
        send(self(), :accept_stream)
        {:noreply, state}

      {:error, :timeout} ->
        # Normal case - no streams to accept right now
        send(self(), :accept_stream)
        {:noreply, state}

      {:error, reason} when reason in [:badarg, :internal_error, :bad_pid, :owner_dead] ->
        log(:error, "Stream accept error: #{inspect(reason)}")
        send(self(), :accept_stream)
        {:noreply, state}
    end
  end

  def handle_info({:quic, data, stream, props}, state) when is_binary(data) do
    <<protocol_id::8, _::binary>> = data

    if protocol_id < 128 do
      # UP stream handling
      log(:debug, "Received UP stream data")
      handle_up_stream_data(protocol_id, data, stream, state)
    else
      # CE stream handling (no need to track state)
      handle_stream_data(
        data,
        stream,
        props,
        state,
        log_tag: "[QUIC_SERVER]",
        on_complete: fn protocol_id, message, stream ->
          response =
            case protocol_id do
              128 ->
                blocks_bin = Network.Calls.call(128, message)
                encode_message(protocol_id, blocks_bin)
              _ ->
                encode_message(protocol_id, message)
            end
          {:ok, _} = :quicer.send(stream, response, Flags.send_flag(:fin))
          {:noreply, state}
        end
      )
    end
  end

  def handle_info({:quic, :stream_closed, stream, _props}, state) do
    log(:info, "Stream closed: #{inspect(stream)}")
    {:noreply, %{state | streams: Map.delete(state.streams, stream)}}
  end

  def handle_info({:quic, event_name, _stream, _props} = _msg, state) do
    log(:debug, "Received unhandled event: #{inspect(event_name)}")

    {:noreply, state}
  end

  defp handle_up_stream_data(protocol_id, data, stream, state) do
    log(:debug, "Handling UP stream data: protocol=#{protocol_id}")
    # First handle stream state management
    {stream_state, new_state} = manage_up_stream(protocol_id, stream, state)

    case stream_state do
      {:ok, current_stream} ->
        # Process the data for valid stream
        process_stream_data(protocol_id, data, current_stream, new_state)

      :reject ->
        # Stream was rejected (lower ID)
        log(:info, "Rejected UP stream with lower ID: #{inspect(stream)}")
        {:noreply, new_state}
    end
  end

  # Handles stream state management, returns {stream_state, new_server_state}
  defp manage_up_stream(protocol_id, stream, state) do
    current = Map.get(state.up_streams, protocol_id)

    cond do
      # Existing stream with matching ID
      current != nil and stream == current.stream_id ->
        log(:debug, "Using existing UP stream: #{inspect(stream)}")
        {{:ok, current}, state}

      # New stream or higher ID - reset old and accept new
      current == nil or stream > current.stream_id ->
        if current do
          log(:info, "Replacing UP stream #{inspect(current.stream_id)} with #{inspect(stream)}")
          :quicer.shutdown_stream(current.stream_id)
        else
          log(:info, "Registering new UP stream: #{inspect(stream)}")
        end

        new_stream = %{
          stream_id: stream,
          buffer: <<>>
        }

        new_state = put_in(state.up_streams[protocol_id], new_stream)
        {{:ok, new_stream}, new_state}

      # Lower stream ID - reject
      true ->
        log(
          :info,
          "Rejecting UP stream with lower ID: current=#{inspect(current.stream_id)}, new=#{inspect(stream)}"
        )

        :quicer.shutdown_stream(stream)
        {:reject, state}
    end
  end

  # Handles actual data processing for a valid stream
  defp process_stream_data(protocol_id, data, stream_state, state) do
    # log(:debug, "Processing stream data: protocol=#{protocol_id}, size=#{byte_size(data)}")
    buffer_ = stream_state.buffer <> data

    case process_up_stream_buffer(buffer_) do
      {:need_more, _buffer} ->
        # log(:debug, "Buffering incomplete message: #{byte_size(buffer_)} bytes")
        new_state = put_in(state.up_streams[protocol_id].buffer, buffer_)
        {:noreply, new_state}

      {:complete, message} ->
        # this is blocking, it should be non-blocking
        log(:debug, "complete block announcement")
        # Network.Calls.call(protocol_id, message)
        new_state = put_in(state.up_streams[protocol_id].buffer, <<>>)
        {:noreply, new_state}
    end
  end

  defp process_up_stream_buffer(buffer) do
    cond do
      byte_size(buffer) < 5 ->
        log(:debug, "Buffer too small (#{byte_size(buffer)} bytes), need at least 5")
        {:need_more, buffer}

      byte_size(buffer) >= 5 ->
        <<protocol_id::8, message_size::32-little, rest::binary>> = buffer
        log(:debug, "Got message header: protocol=#{protocol_id}, size=#{message_size}, rest=#{byte_size(rest)} bytes")

        if byte_size(rest) >= message_size do
          <<message::binary-size(message_size), remaining::binary>> = rest
          log(:debug, "Extracted complete message: size=#{message_size}, remaining=#{byte_size(remaining)}")
          {:complete, message}
        else
          log(:debug, "Incomplete message: have #{byte_size(rest)}, need #{message_size}")
          {:need_more, buffer}
        end
    end
  end
end
