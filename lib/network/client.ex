defmodule Network.Client do
  alias Network.PeerState
  import Quicer.Flags
  import Network.{MessageHandler, Codec, Config}
  require Logger
  use Codec.Encoder

  @log_context "[QUIC_CLIENT]"

  def log(level, message), do: Logger.log(level, "#{@log_context} #{message}")

  def send(pid, protocol_id, message) when is_integer(protocol_id) do
    GenServer.call(pid, {:send, protocol_id, message}, 5_000)
  end

  def request_blocks(pid, hash, direction, max_blocks) when direction in [0, 1] do
    message = hash <> <<direction::8>> <> <<max_blocks::32>>
    send(pid, 128, message)
  end

  def announce_block(pid, header, slot) do
    log(:debug, "Announcing block at slot #{slot}")
    encoded_header = e(header)
    hash = h(encoded_header)
    messsage = encoded_header <> hash <> <<slot::32>>
    GenServer.cast(pid, {:announce_block, messsage, hash, slot})
  end

  def handle_cast(
        {:announce_block, message, hash, slot},
        %PeerState{up_streams: up_streams} = state
      ) do
    protocol_id = 0

    {stream, state_} =
      case Map.get(up_streams, protocol_id) do
        # Existing stream - use it without state update
        %{stream_id: stream_id} ->
          log(:debug, "Reusing existing UP stream for block announcement")
          {stream_id, state}

        # No stream - create new one and update state
        nil ->
          log(:info, "Creating new UP stream for block announcements")
          {:ok, stream} = :quicer.start_stream(state.connection, default_stream_opts())
          state_ = put_in(state.up_streams[protocol_id], %{stream_id: stream})
          {stream, state_}
      end

    log(:debug, "Sending block announcement: hash=#{inspect(hash)}, slot=#{slot}")
    {:ok, _} = :quicer.send(stream, encode_message(protocol_id, message), send_flag(:none))
    {:noreply, state_}
  end

  def handle_call({:send, protocol_id, message}, from, %PeerState{} = state) do
    {:ok, stream} = :quicer.start_stream(state.connection, default_stream_opts())
    {:ok, _} = :quicer.send(stream, encode_message(protocol_id, message), send_flag(:fin))

    new_state = %PeerState{
      state
      | outgoing_streams:
          Map.put(state.outgoing_streams, stream, %{
            from: from
          })
    }

    {:noreply, new_state}
  end

  def handle_data(data, stream, props, %PeerState{} = state) do
    handle_stream_data(data, stream, props, state,
      log_tag: "[QUIC_CLIENT]",
      on_complete: fn protocol_id, message, stream ->
        case protocol_id >= 128 and Map.get(state.outgoing_streams, stream) do
          %{from: from} ->
            response = Network.ClientCalls.call(protocol_id, message)
            GenServer.reply(from, response)

          _ ->
            Task.start(fn -> Network.ClientCalls.call(protocol_id, message) end)
        end
      end
    )
  end
end
