defmodule Network.UpStreamManager do
  require Logger
  alias Network.{ConnectionState, StreamUtils}
  alias Util.Logger, as: Log

  def manage_up_stream(protocol_id, stream_ref, %ConnectionState{} = state, log_tag) do
    current_stream_ref = Map.get(state.up_streams, protocol_id, %{}) |> Map.get(:stream)

    cond do
      # Existing stream with matching ID
      current_stream_ref != nil and stream_ref == current_stream_ref ->
        Log.stream(:debug, "#{log_tag} Using existing UP stream", stream_ref, protocol_id)
        stream_data = Map.get(state.up_stream_data, stream_ref)
        {{:ok, stream_data}, state}

      # New stream or higher ID - reset old and accept new
      current_stream_ref == nil or stream_ref > current_stream_ref ->
        if current_stream_ref do
          current_id = StreamUtils.format_stream_ref(current_stream_ref)
          new_id = StreamUtils.format_stream_ref(stream_ref)
          Log.stream(:debug, "#{log_tag} Replacing UP stream: #{current_id} -> #{new_id}", stream_ref, protocol_id)

          # :quicer.shutdown_stream(current_stream_ref)
        else
          Log.stream(:debug, "#{log_tag} Registering new UP stream", stream_ref, protocol_id)
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
        Log.stream(:info, "#{log_tag} Rejecting UP stream with lower ID", stream_ref, protocol_id)
        :quicer.shutdown_stream(stream_ref)
        {:reject, state}
    end
  end
end
