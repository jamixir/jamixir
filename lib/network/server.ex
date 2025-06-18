defmodule Network.Server do
  require Logger
  alias Quicer.Flags
  alias Network.Codec
  alias Network.UpStreamManager
  import Bitwise, only: [&&&: 2]
  alias Network.MessageParsers

  @log_context "[QUIC_SERVER]"

  def log(level, message), do: Logger.log(level, "#{@log_context} #{message}")
  def log(message), do: Logger.log(:info, "#{@log_context} #{message}")

  def handle_info(:accept_connection, %{socket: socket} = state) do
    case :quicer.accept(socket, [], :infinity) do
      {:ok, conn} ->
        log("Connection accepted")
        {:ok, conn} = :quicer.handshake(conn)
        log("Handshake completed")
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

  defp get_stream(stream, state) do
    case Map.get(state.ce_streams, stream) do
      nil ->
        case Map.get(state.up_stream_data, stream) do
          nil -> :new_stream
          up -> {:up, up}
        end

      ce ->
        {:ce, ce}
    end
  end

  def handle_ce_stream(
        new_data,
        stream,
        props,
        server_state,
        %{protocol_id: protocol_id, buffer: buffer} = stream_data
      ) do
    log(:debug, "CE STREAM: #{inspect(new_data)}")
    updated_buffer = buffer <> new_data

    state_ =
      if (props.flags &&& Flags.receive_flag(:fin)) != 0 do
        messages = MessageParsers.parse_ce_messages(updated_buffer)

        responses =
          case Network.ServerCalls.call(protocol_id, messages) do
            m when is_list(m) -> m
            m when is_binary(m) -> [m]
          end

        all_but_last = Enum.drop(responses, -1)

        for r <- all_but_last,
            do: :quicer.send(stream, Codec.encode_message(r), Flags.send_flag(:none))

        :quicer.send(stream, Codec.encode_message(List.last(responses)), Flags.send_flag(:fin))

        %{server_state | ce_streams: Map.delete(server_state.ce_streams, stream)}
      else
        updated_stream = put_in(stream_data.buffer, updated_buffer)

        %{
          server_state
          | ce_streams: Map.put(server_state.ce_streams, stream, updated_stream)
        }
      end

    {:noreply, state_}
  end

  # Protocol ID is nil, parse it from data
  def handle_up_stream(data, stream, state, %{protocol_id: nil, buffer: buffer} = stream_data) do
    log(:debug, "UP STREAM (protocol not set yet): #{inspect(data)}")
    updated_buffer = buffer <> data

    case MessageParsers.parse_up_protocol_id(updated_buffer) do
      {:need_more, new_buffer} ->
        {:noreply, put_in(state.up_stream_data[stream].buffer, new_buffer)}

      {:protocol, protocol_id, rest} ->
        log(:debug, "Received protocol ID #{protocol_id} for stream #{inspect(stream)}")

        # Update stream with extracted protocol_id
        stream_data = %{stream_data | protocol_id: protocol_id, buffer: rest}
        state = put_in(state.up_stream_data[stream], stream_data)

        handle_up_stream(<<>>, stream, state, stream_data)
    end
  end

  # Protocol ID is known, decode message
  def handle_up_stream(
        data,
        stream,
        state,
        %{protocol_id: protocol_id, buffer: buffer} = _stream_data
      ) do
    server_calls_impl = Application.get_env(:jamixir, :server_calls, Network.ServerCalls)
    log(:debug, "UP STREAM (protocol known): #{inspect(data)}")
    updated_buffer = buffer <> data

    case Codec.decode_messages(updated_buffer) do
      {:need_more, new_buffer} ->
        {:noreply, put_in(state.up_stream_data[stream].buffer, new_buffer)}

      messages when is_list(messages) ->
        Enum.each(messages, fn message ->
          server_calls_impl.call(protocol_id, message)
        end)

        {:noreply, put_in(state.up_stream_data[stream].buffer, <<>>)}
    end
  end

  def handle_data(data, stream, props, state) do
    stream_data = get_stream(stream, state)

    case stream_data do
      {:ce, stream_state} ->
        handle_ce_stream(data, stream, props, state, stream_state)

      {:up, stream_state} ->
        protocol_id = Map.get(stream_state, :protocol_id)

        {{:ok, stream_state}, new_state} =
          UpStreamManager.manage_up_stream(protocol_id, stream, state, @log_context)

        handle_up_stream(data, stream, new_state, stream_state)

      :new_stream ->
        process_new_stream(data, stream, props, state)
    end
  end

  defp process_new_stream(<<protocol_id::8, rest::binary>> = data, stream, props, state) do
    if protocol_id >= 128 do
      handle_ce_stream(rest, stream, props, state, %{protocol_id: protocol_id, buffer: <<>>})
    else
      case UpStreamManager.manage_up_stream(protocol_id, stream, state, @log_context) do
        {{:ok, stream_data}, new_state} ->
          handle_up_stream(data, stream, new_state, stream_data)

        {:reject, _} ->
          {:noreply, state}
      end
    end
  end

  defp process_new_stream(_, _, _, state), do: {:noreply, state}
end
