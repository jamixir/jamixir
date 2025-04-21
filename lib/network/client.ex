defmodule Network.Client do
  alias System.Audit.AuditAnnouncement
  alias Block.Extrinsic.{Disputes.Judgement, TicketProof}
  alias Block.Extrinsic.Assurance
  alias Network.PeerState
  import Quicer.Flags
  import Network.{MessageHandler, Codec, Config}
  require Logger
  use Codec.Encoder
  use Sizes

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

  def handle_call({:send, protocol_id, message}, from, %PeerState{} = state)
      when is_binary(message) do
    handle_call({:send, protocol_id, [message]}, from, state)
  end

  def handle_call({:send, protocol_id, messages}, from, %PeerState{} = state)
      when is_list(messages) do
    log(:debug, "sending messages #{inspect(messages)}")
    {:ok, stream} = :quicer.start_stream(state.connection, default_stream_opts())

    log(:debug, "sending protocol_id #{protocol_id}")

    {:ok, _} = :quicer.send(stream, <<protocol_id::8>>, send_flag(:none))
    {all_but_last, [last_message]} = Enum.split(messages, -1)

    for {m, i} <- Enum.with_index(all_but_last) do
      log(:debug, "sending message number #{i} of #{length(all_but_last)} #{inspect(m)}")
      {:ok, _} = :quicer.send(stream, encode_message(m), send_flag(:none))
    end

    log(:debug, "sending last message #{inspect(last_message)}")
    {:ok, _} = :quicer.send(stream, encode_message(last_message), send_flag(:fin))

    new_pending =
      Map.put(state.pending_responses, stream, %{from: from, protocol_id: protocol_id})

    {:noreply, %PeerState{state | pending_responses: new_pending}}
  end

  def handle_data(data, stream, _props, %PeerState{} = state) do
    msg = decode_messages(data)
    log(:debug, "received messages #{inspect(msg)}")

    case Map.get(state.pending_responses, stream) do
      %{from: from, protocol_id: protocol_id} ->
        response = Network.ClientCalls.call(protocol_id, msg)
        log(:debug, "sending response #{inspect(response)}")
        GenServer.reply(from, response)

      _ ->
        # This stream is not in pending_responses, that means that this is not a CE stream initiated by the client
        # 1. unsolicited data from somewhere, not to handle
        # 2. could be an up_stream, but we expect up stream to be used for cast, not waiting for response

        # so finally we just ignore it
        log(:debug, "ignoring unsolicited data from stream #{inspect(stream)}")
        nil

        # Task.start(fn -> Network.ClientCalls.call(protocol_id, msg) end)
    end

    state_ = %{state | pending_responses: Map.delete(state.pending_responses, stream)}
    {:noreply, state_}
  end
end
