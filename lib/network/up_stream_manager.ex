defmodule Network.UpStreamManager do
  require Logger
  alias Network.ConnectionState

  def manage_up_stream(protocol_id, stream_ref, %ConnectionState{} = state, log_tag) do
    current_stream_ref = Map.get(state.up_streams, protocol_id, %{}) |> Map.get(:stream)

    cond do
      # Existing stream with matching ID
      current_stream_ref != nil and stream_ref == current_stream_ref ->
        Logger.debug("#{log_tag} Using existing UP stream: #{inspect(stream_ref)}")
        stream_data = Map.get(state.up_stream_data, stream_ref)
        {{:ok, stream_data}, state}

      # New stream or higher ID - reset old and accept new
      current_stream_ref == nil or stream_ref > current_stream_ref ->
        if current_stream_ref do
          Logger.info(
            "#{log_tag} Replacing UP stream: #{inspect(current_stream_ref)} -> #{inspect(stream_ref)}"
          )

          # :quicer.shutdown_stream(current_stream_ref)
        else
          Logger.info("#{log_tag} Registering new UP stream: #{inspect(stream_ref)}")
        end

        # The first time the stream is open, protocol ID is not yet recieved => nil
        stream_data = %{protocol_id: nil, buffer: <<>>}

        updated_up_stream_data =
          state.up_stream_data
          |> Map.delete(current_stream_ref)
          |> Map.put(stream_ref, stream_data)

        updated_up_streams = Map.put(state.up_streams, protocol_id, %{stream: stream_ref})

        new_state = %{
          state
          | up_streams: updated_up_streams,
            up_stream_data: updated_up_stream_data
        }

        {{:ok, stream_data}, new_state}

      # Lower stream ID - reject
      true ->
        Logger.info("#{log_tag} Rejecting UP stream with lower ID: #{inspect(stream_ref)}")
        :quicer.shutdown_stream(stream_ref)
        {:reject, state}
    end
  end
end
