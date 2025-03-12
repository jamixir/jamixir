defmodule Network.Client do
  alias Network.PeerState
  import Quicer.Flags
  import Network.{MessageHandler, Codec, Config}
  require Logger
  use Codec.Encoder

  @log_context "[QUIC_CLIENT]"

  def log(level, message), do: Logger.log(level, "#{@log_context} #{message}")
  def log(message), do: Logger.log(:info, "#{@log_context} #{message}")

  def send(pid, protocol_id, message) when is_integer(protocol_id) do
    GenServer.call(pid, {:send, protocol_id, message}, 500)
  end

  def request_blocks(pid, hash, direction, max_blocks) when direction in [0, 1] do
    message = hash <> <<direction::8>> <> <<max_blocks::32>>
    send(pid, 128, message)
  end

  def announce_preimage(pid, service_id, hash, length) do
    message = <<service_id::32-little>> <> hash <> <<length::32-little>>
    send(pid, 142, message)
  end

  def announce_block(pid, header, slot) do
    log(:debug, "Announcing block at slot #{slot}")
    encoded_header = e(header)
    hash = h(encoded_header)
    message = encoded_header <> hash <> <<slot::32>>
    GenServer.cast(pid, {:announce_block, message, hash, slot})
  end

  def handle_cast(
        {:announce_block, message, hash, slot},
        %PeerState{up_streams: up_streams} = state
      ) do
    protocol_id = 0

    {stream, state_} =
      case Map.get(up_streams, protocol_id) do
        # Existing stream - use it without state update
        %{stream: stream} ->
          log(:debug, "Reusing existing UP stream for block announcement")
          {stream, state}

        # No stream - create new one and update state
        nil ->
          log("Creating new UP stream for block announcements")
          {:ok, stream} = :quicer.start_stream(state.connection, default_stream_opts())
          state_ = put_in(state.up_streams[protocol_id], %{stream: stream})
          {stream, state_}
      end

    log(:debug, "Sending block announcement: hash=#{inspect(hash)}, slot=#{slot}")
    {:ok, _} = :quicer.send(stream, encode_message(protocol_id, message), send_flag(:none))
    {:noreply, state_}
  end

  def handle_call({:send, protocol_id, message}, from, %PeerState{} = state) do
    {:ok, stream} = :quicer.start_stream(state.connection, default_stream_opts())
    log("sending message to server: #{protocol_id} #{inspect(message)}")
    {:ok, _} = :quicer.send(stream, encode_message(protocol_id, message), send_flag(:fin))

    new_pending =
      Map.put(state.pending_responses, stream, %{from: from, protocol_id: protocol_id})

    {:noreply, %PeerState{state | pending_responses: new_pending}}
  end

  def handle_data(protocol_id, data, stream, props, %PeerState{} = state) do
    handle_stream_data(protocol_id, data, stream, props, state,
      log_tag: "[QUIC_CLIENT]",
      on_complete: fn protocol_id, message, stream ->
        case protocol_id >= 128 and Map.get(state.pending_responses, stream) do
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
