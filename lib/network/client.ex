defmodule Network.Client do
  alias Network.MessageParsers
  alias Quicer.Flags
  alias System.Audit.AuditAnnouncement
  alias Block.Extrinsic.{Disputes.Judgement, TicketProof}
  alias Block.Extrinsic.Assurance
  alias Network.PeerState
  import Quicer.Flags
  import Network.{Codec, Config}
  require Logger
  use Codec.Encoder
  use Sizes
  import Bitwise, only: [&&&: 2]
  @log_context "[QUIC_CLIENT]"

  def log(level, message), do: Logger.log(level, "#{@log_context} #{message}")
  def log(message), do: Logger.log(:info, "#{@log_context} #{message}")

  def send(pid, protocol_id, message) when is_integer(protocol_id) do
    GenServer.call(pid, {:send, protocol_id, message}, 500)
  end

  def send(pid, protocol_id, messages) when is_list(messages) do
    GenServer.call(pid, {:send, protocol_id, messages}, 500)
  end

  def request_blocks(pid, hash, direction, max_blocks) when direction in [0, 1] do
    message = hash <> <<direction::8>> <> <<max_blocks::32>>
    send(pid, 128, message)
  end

  def announce_preimage(pid, service_id, hash, length) do
    message = <<service_id::m(service_id)>> <> hash <> <<length::32-little>>
    send(pid, 142, message)
  end

  def get_preimage(pid, hash) do
    send(pid, 143, hash)
  end

  def distribute_assurance(
        pid,
        %Assurance{
          hash: <<_::m(hash)>> = hash,
          bitfield: <<_::m(bitfield)>> = bitfield,
          signature: <<_::m(signature)>> = signature
        }
      ) do
    message = hash <> bitfield <> signature
    send(pid, 141, message)
  end

  def distribute_ticket(p, :proxy, epoch, ticket), do: distribute_ticket(p, 131, epoch, ticket)

  def distribute_ticket(p, :validator, epoch, ticket),
    do: distribute_ticket(p, 132, epoch, ticket)

  def distribute_ticket(
        pid,
        mode,
        epoch,
        %TicketProof{
          attempt: a,
          signature: <<_::b(bandersnatch_proof)>> = vrf_proof
        }
      ) do
    message = <<epoch::32-little>> <> <<a>> <> vrf_proof
    send(pid, mode, message)
  end

  def announce_block(pid, header, timeslot) do
    log(:debug, "Announcing block at slot #{timeslot}")
    encoded_header = e(header)
    hash = h(encoded_header)
    message = encoded_header <> hash <> t(timeslot)
    GenServer.cast(pid, {:announce_block, message, hash, timeslot})
  end

  def announce_judgement(pid, epoch_index, <<_::m(hash)>> = hash, %Judgement{
        vote: vote,
        validator_index: validator_index,
        signature: <<_::m(signature)>> = sign
      }) do
    message = t(epoch_index) <> t(validator_index) <> <<vote::8>> <> hash <> sign

    send(pid, 145, message)
  end

  def distribute_guarantee(pid, %Block.Extrinsic.Guarantee{} = guarantee) do
    send(pid, 135, e(guarantee))
  end

  def get_work_report(pid, <<_::m(hash)>> = hash) do
    send(pid, 136, hash)
  end

  def request_segment(pid, erasure_root, segment_index),
    do: send_segment_request(pid, 137, erasure_root, segment_index)

  def request_audit_shard(pid, erasure_root, segment_index),
    do: send_segment_request(pid, 138, erasure_root, segment_index)

  defp send_segment_request(pid, protocol_id, erasure_root, segment_index) do
    message = erasure_root <> <<segment_index::16-little>>
    send(pid, protocol_id, message)
  end

  def send_work_package(pid, wp, core_index, extrinsics) do
    messages = [t(core_index) <> e(wp), extrinsics]
    send(pid, 133, messages)
  end

  def send_work_package_bundle(pid, bundle, core_index, segment_roots) do
    messages = [t(core_index) <> e(segment_roots), bundle]
    send(pid, 134, messages)
  end

  def announce_audit(pid, %AuditAnnouncement{
        tranche: tranche,
        announcements: announcements,
        header_hash: header_hash,
        signature: signature,
        evidence: evidence
      }) do
    announcements =
      for {core_index, hash} <- announcements do
        <<core_index::m(core_index)>> <> <<hash::b(hash)>>
      end

    m1 =
      <<header_hash::b(hash)>> <>
        <<tranche::8>> <> e(vs(announcements)) <> <<signature::b(signature)>>

    send(pid, 144, [m1, evidence])
  end

  def handle_cast(
        {:announce_block, message, hash, slot},
        %PeerState{up_streams: up_streams} = state
      ) do
    protocol_id = 0

    case Map.get(up_streams, protocol_id) do
      # Existing stream - reuse it and send only the message
      %{stream: stream} ->
        log(:debug, "Reusing existing UP stream for block announcement")
        log(:debug, "Sending block announcement: hash=#{inspect(hash)}, slot=#{slot}")

        case :quicer.send(stream, encode_message(message), send_flag(:none)) do
          {:ok, _} ->
            {:noreply, state}

          {:error, reason} ->
            log(:error, "Failed to send QUIC message: #{inspect(reason)}")
            {:noreply, state}
        end

        {:noreply, state}

      # No stream yet - send protocol ID first, then the message
      nil ->
        log("Creating new UP stream for block announcements")
        {:ok, stream} = :quicer.start_stream(state.connection, default_stream_opts())
        state = put_in(state.up_streams[protocol_id], %{stream: stream})
        state = put_in(state.up_stream_data[stream], %{protocol_id: protocol_id, buffer: <<>>})

        log(:debug, "Sending block announcement: hash=#{inspect(hash)}, slot=#{slot}")
        {:ok, _} = :quicer.send(stream, <<protocol_id::8>>, send_flag(:none))
        {:ok, _} = :quicer.send(stream, encode_message(message), send_flag(:none))

        {:noreply, state}
    end
  end

  def handle_call({:send, protocol_id, message}, from, %PeerState{} = state)
      when is_binary(message) do
    handle_call({:send, protocol_id, [message]}, from, state)
  end

  def handle_call({:send, protocol_id, messages}, from, %PeerState{} = state)
      when is_list(messages) do
    {:ok, stream} = :quicer.start_stream(state.connection, default_stream_opts())

    {:ok, _} = :quicer.send(stream, <<protocol_id::8>>, send_flag(:none))
    {all_but_last, [last_message]} = Enum.split(messages, -1)

    Enum.each(all_but_last, fn m ->
      {:ok, _} = :quicer.send(stream, encode_message(m), send_flag(:none))
    end)

    {:ok, _} = :quicer.send(stream, encode_message(last_message), send_flag(:fin))

    new_pending =
      Map.put(state.pending_responses, stream, %{
        from: from,
        protocol_id: protocol_id,
        buffer: <<>>
      })

    {:noreply, %PeerState{state | pending_responses: new_pending}}
  end

  def handle_data(data, stream, props, %PeerState{} = state) do
    state_ =
      case Map.get(state.pending_responses, stream) do
        nil ->
          # This stream is not in pending_responses, that means that this is not a CE stream initiated by the client
          # 1. unsolicited data from somewhere, not to handle
          # 2. could be an up_stream, but we expect up stream to be used for cast, not waiting for response

          # so finally we just ignore it
          log(:debug, "ignoring unsolicited data from stream #{inspect(stream)}")
          state

        # Task.start(fn -> Network.ClientCalls.call(protocol_id, msg) end)
        stream_data ->
          updated_buffer = stream_data.buffer <> data

          if (props.flags &&& Flags.receive_flag(:fin)) != 0 do
            messages = MessageParsers.parse_ce_messages(updated_buffer)

            # Apply protocol-specific message parsing
            processed_messages =
              MessageParsers.parse_protocol_specific_messages(stream_data.protocol_id, messages)

            response = Network.ClientCalls.call(stream_data.protocol_id, processed_messages)

            GenServer.reply(stream_data.from, response)
            %{state | pending_responses: Map.delete(state.pending_responses, stream)}
          else
            %{
              state
              | pending_responses:
                  Map.put(state.pending_responses, stream, %{stream_data | buffer: updated_buffer})
            }
          end
      end

    {:noreply, state_}
  end
end
