defmodule Network.MessageHandler do
  require Logger
  import Bitwise
  alias Quicer.Flags

  def handle_ce_stream_data(
        data,
        stream,
        %{flags: flags} = props,
        %{streams: streams} = state,
        opts \\ []
      ) do
    log_tag = Keyword.get(opts, :log_tag, "[MESSAGE_HANDLER]")
    on_complete = Keyword.get(opts, :on_complete)

    Logger.debug("#{log_tag} Props: #{inspect(props)}")
    Logger.debug("#{log_tag} Data: #{inspect(data)}")

    stream_state = Map.get(streams, stream, %{})
    buffer_ = Map.get(stream_state, :buffer, <<>>) <> data
    Logger.debug("#{log_tag} buffer_: #{inspect(buffer_)}")

    if (flags &&& Flags.receive_flag(:fin)) != 0 do
      Logger.debug("#{log_tag} FIN flag is set")
      <<protocol_id::8, length::32-little, message::binary-size(length)>> = buffer_

      case on_complete do
        nil ->
          {:noreply, state}

        func when is_function(func) ->
          func.(protocol_id, message, stream)
          {:noreply, state}
      end
    else
      Logger.debug("#{log_tag} More data coming, keep buffering")
      stream_state_ = Map.put(stream_state, :buffer, buffer_)
      {:noreply, %{state | streams: Map.put(state.streams, stream, stream_state_)}}
    end
  end

  def handle_up_stream_data(
        protocol_id,
        data,
        stream,
        state,
        opts \\ []
      ) do
    log_tag = Keyword.get(opts, :log_tag, "[MESSAGE_HANDLER]")
    # First handle stream state management
    {stream_state, new_state} = manage_stream(protocol_id, stream, state, opts)

    case stream_state do
      {:ok, current_stream} ->
        # Process the data for valid stream
        process_stream_data(protocol_id, data, current_stream, new_state, opts)

      :reject ->
        # Stream was rejected (lower ID)
        Logger.info("#{log_tag} Rejected UP stream with lower ID: #{inspect(stream)}")
        {:noreply, new_state}
    end
  end

  # Handles stream state management, returns {stream_state, new_server_state}
  defp manage_stream(protocol_id, stream_id, state, opts) do
    log_tag = Keyword.get(opts, :log_tag, "[MESSAGE_HANDLER]")
    current = Map.get(state.up_streams, protocol_id)

    cond do
      # Existing stream with matching ID
      current != nil and stream_id == current.stream_id ->
        Logger.debug("#{log_tag} Using existing UP stream: #{inspect(stream_id)}")
        {{:ok, current}, state}

      # New stream or higher ID - reset old and accept new
      current == nil or stream_id > current.stream_id ->
        if current do
          Logger.info(
            "#{log_tag} Replacing UP stream #{inspect(current.stream_id)} with #{inspect(stream_id)}"
          )

          :quicer.shutdown_stream(current.stream_id)
        else
          Logger.info("#{log_tag} Registering new UP stream: #{inspect(stream_id)}")
        end

        new_stream = %{
          stream_id: stream_id,
          buffer: <<>>
        }

        new_state = put_in(state.up_streams[protocol_id], new_stream)
        {{:ok, new_stream}, new_state}

      # Lower stream ID - reject
      true ->
        Logger.info(
          "#{log_tag} Rejecting UP stream with lower ID: current=#{inspect(current.stream_id)}, new=#{inspect(stream_id)}"
        )

        :quicer.shutdown_stream(stream_id)
        {:reject, state}
    end
  end

  # Handles actual data processing for a valid stream
  defp process_stream_data(protocol_id, data, stream_state, state, opts) do
    log_tag = Keyword.get(opts, :log_tag, "[MESSAGE_HANDLER]")
    on_complete = Keyword.get(opts, :on_complete)

    Logger.debug(
      "#{log_tag} Processing stream data: protocol=#{protocol_id}, size=#{byte_size(data)}"
    )

    buffer_ = stream_state.buffer <> data

    case process_up_stream_buffer(buffer_) do
      {:need_more, _buffer} ->
        Logger.debug("#{log_tag} Buffering incomplete message: #{byte_size(buffer_)} bytes")
        new_state = put_in(state.up_streams[protocol_id].buffer, buffer_)
        {:noreply, new_state}

      {:complete, message} ->
        Logger.debug("#{log_tag} Processing complete message: #{byte_size(message)} bytes")
        on_complete.(protocol_id, message, stream_state.stream_id)

        new_state = put_in(state.up_streams[protocol_id].buffer, <<>>)
        {:noreply, new_state}
    end
  end

  defp process_up_stream_buffer(buffer, opts \\ []) do
    log_tag = Keyword.get(opts, :log_tag, "[MESSAGE_HANDLER]")

    cond do
      byte_size(buffer) < 5 ->
        Logger.debug("#{log_tag} Buffer too small (#{byte_size(buffer)} bytes), need at least 5")
        {:need_more, buffer}

      byte_size(buffer) >= 5 ->
        <<protocol_id::8, message_size::32-little, rest::binary>> = buffer

        Logger.debug(
          "#{log_tag} Got message header: protocol=#{protocol_id}, size=#{message_size}, rest=#{byte_size(rest)} bytes"
        )

        if byte_size(rest) >= message_size do
          <<message::binary-size(message_size), remaining::binary>> = rest

          Logger.debug(
            "#{log_tag} Extracted complete message: size=#{message_size}, remaining=#{byte_size(remaining)}"
          )

          {:complete, message}
        else
          Logger.debug(
            "#{log_tag} Incomplete message: have #{byte_size(rest)}, need #{message_size}"
          )

          {:need_more, buffer}
        end
    end
  end

  def encode_message(protocol_id, message) do
    length = byte_size(message)
    <<protocol_id::8, length::32-little, message::binary>>
  end
end
