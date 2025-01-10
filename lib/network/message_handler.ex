defmodule Network.MessageHandler do
  require Logger
  import Bitwise
  alias Quicer.Flags

  def handle_stream_data(
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

  def encode_message(protocol_id, message) do
    length = byte_size(message)
    <<protocol_id::8, length::32-little, message::binary>>
  end
end
