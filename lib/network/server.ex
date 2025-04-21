defmodule Network.Server do
  require Logger
  alias Quicer.Flags
  import Network.{MessageHandler, Codec}
  import Bitwise, only: [&&&: 2]

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

  defp parse_messages(<<>>, acc) do
    log(:debug, "PARSE_MESSAGES: Empty binary, returning accumulated messages: #{length(acc)}")
    Enum.reverse(acc)
  end

  defp parse_messages(buffer, acc) do
    log(
      :debug,
      "PARSE_MESSAGES: Processing buffer of size #{byte_size(buffer)}, current messages: #{length(acc)}"
    )

    case buffer do
      <<length::32-little, rest::binary>> ->
        log(
          :debug,
          "PARSE_MESSAGES: Message length: #{length}, remaining buffer size: #{byte_size(rest)}"
        )

        case rest do
          <<message::binary-size(length), remaining::binary>> ->
            log(
              :debug,
              "PARSE_MESSAGES: Extracted message of size #{byte_size(message)}, remaining buffer size: #{byte_size(remaining)}"
            )

            message_preview =
              if byte_size(message) > 0 do
                inspect(binary_part(message, 0, min(16, byte_size(message))))
              else
                "empty"
              end

            log(:debug, "PARSE_MESSAGES: Message preview: #{message_preview}")

            parse_messages(remaining, [message | acc])

          _ ->
            log(
              :error,
              "PARSE_MESSAGES: Buffer incomplete. Length header: #{length}, but only #{byte_size(rest)} bytes available"
            )

            # Not enough data for a complete message - shouldn't happen with FIN flag
            log(:debug, "PARSE_MESSAGES: Returning accumulated messages: #{length(acc)}")
            Enum.reverse(acc)
        end

      malformed ->
        log(
          :error,
          "PARSE_MESSAGES: Malformed buffer without proper length header. Size: #{byte_size(malformed)}, Preview: #{inspect(binary_part(malformed, 0, min(16, byte_size(malformed))))}"
        )

        Enum.reverse(acc)
    end
  end

  def handle_data(data, stream, props, state) do
    stream_id = "#{inspect(stream)}"

    log(
      :debug,
      "RECEIVE: Stream #{stream_id}, data size: #{byte_size(data)}, FIN: #{(props.flags &&& Flags.receive_flag(:fin)) != 0}"
    )

    server_stream = Map.get(state.server_streams, stream)

    # Check if this is an existing stream or a new one
    if server_stream do
      protocol_id = server_stream.protocol_id
      existing_buffer = server_stream.buffer

      updated_buffer =
        existing_buffer <> data

      updated_state = %{
        state
        | server_streams:
            Map.put(state.server_streams, stream, %{server_stream | buffer: updated_buffer})
      }

      # Check if this is the final data chunk (FIN flag)
      if (props.flags &&& Flags.receive_flag(:fin)) != 0 do
        log(:debug, "FIN FLAG DETECTED - processing buffer of size #{byte_size(updated_buffer)}")

        # Parse all messages from the buffer with detailed logging
        messages = parse_messages(updated_buffer, [])
        log(:debug, "Parsed #{length(messages)} messages from buffer")

        # Call server to process messages and get response
        response = Network.ServerCalls.call(protocol_id, messages)

        :quicer.send(stream, encode_message(response), Flags.send_flag(:fin))
        log(:debug, "Response sent, size: #{byte_size(encode_message(response))}")

        # Clean up state
        cleaned_state = %{
          updated_state
          | server_streams: Map.delete(updated_state.server_streams, stream)
        }

        {:noreply, cleaned_state}
      else
        # Not finished yet, just update buffer
        log(:debug, "Partial data received (no FIN), buffer size: #{byte_size(updated_buffer)}")
        {:noreply, updated_state}
      end
    else
      # New stream handling
      case data do
        <<protocol_id::8, rest::binary>> ->
          log(:debug, "NEW STREAM: Protocol ID #{protocol_id}, data size: #{byte_size(rest)}")

          # Create new stream entry
          updated_state = %{
            state
            | server_streams:
                Map.put(state.server_streams, stream, %{protocol_id: protocol_id, buffer: rest})
          }

          # If FIN flag is set, process immediately
          if (props.flags &&& Flags.receive_flag(:fin)) != 0 do
            log(:debug, "FIN FLAG on new stream - processing immediately")

            messages = parse_messages(rest, [])
            log(:debug, "Parsed #{length(messages)} messages from new stream")

            # Process messages and respond
            response = Network.ServerCalls.call(protocol_id, messages)
            :quicer.send(stream, encode_message(response), Flags.send_flag(:fin))

            # Clean up state
            cleaned_state = %{
              updated_state
              | server_streams: Map.delete(updated_state.server_streams, stream)
            }

            {:noreply, cleaned_state}
          else
            {:noreply, updated_state}
          end

        _invalid_data ->
          log(:error, "INVALID DATA FORMAT: Expected protocol ID byte")
          :quicer.send(stream, "INVALID_FORMAT", Flags.send_flag(:fin))
          {:noreply, state}
      end
    end
  end
end
