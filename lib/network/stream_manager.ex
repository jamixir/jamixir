defmodule Network.StreamManager do
  require Logger
  alias Network.PeerState
  def manage_up_stream(protocol_id, stream_ref, %PeerState{} = state, log_tag) do
    current = Map.get(state.up_streams, protocol_id)

    cond do
      # Existing stream with matching ID
      current != nil and stream_ref == current.stream ->
        Logger.debug("#{log_tag} Using existing UP stream: #{inspect(stream_ref)}")
        {{:ok, current}, state}

      # New stream or higher ID - reset old and accept new
      current == nil or stream_ref > current.stream ->
        if current do
          Logger.info(
            "#{log_tag} Replacing UP stream: #{inspect(current.stream)} -> #{inspect(stream_ref)}"
          )

          :quicer.shutdown_stream(current.stream)
          # clear up it's buffer
          Map.delete(state.stream_buffers, current.stream)
        else
          Logger.info("#{log_tag} Registering new UP stream: #{inspect(stream_ref)}")
        end

        new_stream = %{
          stream: stream_ref
        }

        new_state = put_in(state.up_streams[protocol_id], new_stream)
        {{:ok, new_stream}, new_state}

      # Lower stream ID - reject
      true ->
        Logger.info("#{log_tag} Rejecting UP stream with lower ID: #{inspect(stream_ref)}")
        :quicer.shutdown_stream(stream_ref)
        {:reject, state}
    end
  end
end
