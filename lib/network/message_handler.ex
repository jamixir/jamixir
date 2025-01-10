defmodule Network.MessageHandler do
  require Logger
  import Bitwise
  alias Quicer.Flags

  def handle_stream_data(data, stream, %{flags: flags} = props, state, opts \\ []) do
    log_tag = Keyword.get(opts, :log_tag, "[MESSAGE_HANDLER]")
    on_complete = Keyword.get(opts, :on_complete)

    Logger.debug("#{log_tag} Props: #{inspect(props)}")
    Logger.debug("#{log_tag} Data: #{inspect(data)}")

    # Get the binary buffer from the stream state
    stream_state = Map.get(state.streams, stream, %{})
    buffer = Map.get(stream_state, :buffer, <<>>)
    new_buffer = buffer <> data
    Logger.debug("#{log_tag} new_buffer: #{inspect(new_buffer)}")

    if (flags &&& Flags.receive_flag(:fin)) != 0 do
      Logger.debug("#{log_tag} FIN flag is set")
      <<protocol_id::8, length::32-little, message::binary-size(length)>> = new_buffer

      case on_complete do
        nil ->
          {:noreply, state}

        func when is_function(func) ->
          func.(protocol_id, message, stream)
          {:noreply, state}
      end
    else
      Logger.debug("#{log_tag} More data coming, keep buffering")
      # Preserve other stream state fields while updating the buffer
      new_stream_state = Map.put(stream_state, :buffer, new_buffer)
      {:noreply, %{state | streams: Map.put(state.streams, stream, new_stream_state)}}
    end
  end

  def encode_message(protocol_id, message) do
    length = byte_size(message)
    <<protocol_id::8, length::32-little, message::binary>>
  end
end
