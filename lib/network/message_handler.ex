defmodule Network.MessageHandler do
  require Logger
  import Bitwise
  import Network.{Codec, StreamManager}
  alias Network.PeerState
  alias Quicer.Flags

  def handle_stream_data(protocol_id, data, stream, props, %PeerState{} = state, opts \\ []) do
    log_tag = Keyword.get(opts, :log_tag, "[MESSAGE_HANDLER]")
    buffer = Map.get(state.stream_buffers, stream, <<>>) <> data

    mode = if protocol_id < 128, do: :up, else: :ce
    opts = Keyword.put(opts, :mode, mode)

    case mode do
      :up ->
        {stream_state, new_state} = manage_up_stream(protocol_id, stream, state, log_tag)

        case stream_state do
          {:ok, _current_stream} ->
            process_stream_data(protocol_id, data, stream, props, new_state, opts)

          :reject ->
            Logger.info("#{log_tag} Rejected UP stream: #{inspect(stream)}")
            {:noreply, new_state}
        end

      :ce ->
        process_stream_data(protocol_id, buffer, stream, props, state, opts)
    end
  end

  defp process_stream_data(
         protocol_id,
         buffer,
         stream,
         props,
         %PeerState{} = state,
         opts
       ) do
    log_tag = Keyword.get(opts, :log_tag)
    mode = Keyword.get(opts, :mode)
    on_complete = Keyword.get(opts, :on_complete)

    case check_message_complete(mode, buffer, props, log_tag) do
      {:need_more, remaining} ->
        handle_incomplete(mode, remaining, stream, state, log_tag)

      {:complete, message, _remaining} ->
        handle_complete(mode, protocol_id, message, stream, state, on_complete, log_tag)

      :invalid_format ->
        Logger.error("#{log_tag} Dropping stream due to invalid message format")
        :quicer.shutdown_stream(stream)
        {:noreply, state}
    end
  end

  defp check_message_complete(:up, buffer, _props, log_tag) do
    cond do
      byte_size(buffer) < 5 ->
        Logger.debug("#{log_tag} Buffer too small: #{byte_size(buffer)} bytes")
        {:need_more, buffer}

      byte_size(buffer) >= 5 ->
        <<protocol_id::8, message_size::32-little, rest::binary>> = buffer

        Logger.debug(
          "#{log_tag} Message header: size=#{message_size}, rest=#{byte_size(rest)} bytes"
        )

        if byte_size(rest) >= message_size do
          <<message::binary-size(message_size), remaining::binary>> = rest
          {:complete, <<protocol_id::8, message_size::32-little, message::binary>>, remaining}
        else
          {:need_more, buffer}
        end
    end
  end

  defp check_message_complete(:ce, data, %{flags: flags}, log_tag) do
    if (flags &&& Flags.receive_flag(:fin)) != 0 do
      case data do
        <<length::32-little, _msg::binary-size(length), _rest::binary>> ->
          Logger.debug("#{log_tag} CE message complete: size=#{length}")
          {:complete, data, <<>>}

        <<_protocol_id::8, length::32-little, _msg::binary-size(length), _rest::binary>> ->
          Logger.debug("#{log_tag} CE message complete: size=#{length}")
          {:complete, data, <<>>}

        _ ->
          Logger.error("#{log_tag} Invalid CE message format")
          :invalid_format
      end
    else
      Logger.debug("#{log_tag} More data coming, buffering: #{byte_size(data)} bytes")
      {:need_more, data}
    end
  end

  defp handle_incomplete(mode, data, stream, %PeerState{} = state, log_tag) do
    Logger.debug("#{log_tag} Buffering incomplete #{mode} message: #{byte_size(data)} bytes")
    {:noreply, %{state | stream_buffers: Map.put(state.stream_buffers, stream, data)}}
  end

  defp handle_complete(
         mode,
         protocol_id,
         message,
         stream,
         %PeerState{} = state,
         on_complete,
         log_tag
       ) do
    Logger.info("#{log_tag} Processing complete #{mode} message: #{byte_size(message)} bytes")
    message = decode_message(message)
    on_complete.(protocol_id, message, stream)
    new_state = %{state | stream_buffers: Map.delete(state.stream_buffers, stream)}
    {:noreply, new_state}
  end
end
