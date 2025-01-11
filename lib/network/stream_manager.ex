defmodule Network.StreamManager do
  require Logger

  def manage_up_stream(protocol_id, stream_id, state, log_tag) do
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
            "#{log_tag} Replacing UP stream: #{inspect(current.stream_id)} -> #{inspect(stream_id)}"
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
        Logger.info("#{log_tag} Rejecting UP stream with lower ID: #{inspect(stream_id)}")
        :quicer.shutdown_stream(stream_id)
        {:reject, state}
    end
  end
end
