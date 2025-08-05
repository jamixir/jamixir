defmodule Network.Client do
  @behaviour Network.ClientAPI

  alias Network.MessageParsers
  alias Quicer.Flags
  alias System.Audit.AuditAnnouncement
  alias Block.Extrinsic.{Disputes.Judgement, TicketProof}
  alias Block.Extrinsic.Assurance
  alias Network.ConnectionState
  import Quicer.Flags
  import Network.{Codec, Config}
  import Codec.Encoder
  use Sizes
  import Bitwise, only: [&&&: 2]
  alias Util.Logger

  @log_context "[QUIC_CLIENT]"

  def log(level, message), do: Logger.log(level, message, @log_context)
  def log(message), do: Logger.info(message, @log_context)

  @impl true
  def send(pid, protocol_id, message) when is_integer(protocol_id) do
    GenServer.call(pid, {:send, protocol_id, message}, 500)
  end

  @impl true
  def send(pid, protocol_id, messages) when is_list(messages) do
    GenServer.call(pid, {:send, protocol_id, messages}, 500)
  end

  @impl true
  def request_blocks(pid, hash, direction, max_blocks) when direction in [0, 1] do
    message = hash <> <<direction::8>> <> <<max_blocks::32-little>>
    send(pid, 128, message)
  end

  @impl true
  def request_state(
        pid,
        <<block_hash::b(hash)>>,
        <<start_key::binary-size(31)>>,
        <<end_key::binary-size(31)>>,
        max_size
      ) do
    message = block_hash <> start_key <> end_key <> <<max_size::32-little>>
    send(pid, 129, message)
  end

  @impl true
  def announce_preimage(pid, service_id, hash, length) do
    message = <<service_id::m(service_id)>> <> hash <> <<length::32-little>>
    send(pid, 142, message)
  end

  @impl true
  def get_preimage(pid, hash) do
    send(pid, 143, hash)
  end

  @impl true
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

  @impl true
  def distribute_ticket(p, :proxy, epoch, ticket), do: distribute_ticket(p, 131, epoch, ticket)

  @impl true
  def distribute_ticket(p, :validator, epoch, ticket),
    do: distribute_ticket(p, 132, epoch, ticket)

  @impl true
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

  @impl true
  def announce_block(pid, header, timeslot) do
    log(:debug, "Announcing block at slot #{timeslot}")
    encoded_header = e(header)
    hash = h(encoded_header)
    message = encoded_header <> hash <> t(timeslot)
    GenServer.cast(pid, {:announce_block, message, hash, timeslot})
  end

  @impl true
  def announce_judgement(pid, epoch_index, <<_::m(hash)>> = hash, %Judgement{
        vote: vote,
        validator_index: validator_index,
        signature: <<_::m(signature)>> = sign
      }) do
    message = t(epoch_index) <> t(validator_index) <> <<vote::8>> <> hash <> sign

    send(pid, 145, message)
  end

  @impl true
  def distribute_guarantee(pid, %Block.Extrinsic.Guarantee{} = guarantee) do
    send(pid, 135, e(guarantee))
  end

  @impl true
  def get_work_report(pid, <<_::m(hash)>> = hash) do
    send(pid, 136, hash)
  end

  @impl true
  def request_work_report_shard(pid, erasure_root, shard_index),
    do: send_wp_shard_request(pid, 137, erasure_root, shard_index)

  @impl true
  def request_audit_shard(pid, erasure_root, shard_index),
    do: send_wp_shard_request(pid, 138, erasure_root, shard_index)

  defp send_wp_shard_request(pid, protocol_id, erasure_root, shard_index) do
    message = erasure_root <> <<shard_index::16-little>>
    send(pid, protocol_id, message)
  end

  @impl true
  def request_segment_shards(pid, requests, with_justification) do
    message =
      for r <- requests, reduce: <<>> do
        acc ->
          indexes =
            for index <- r.shard_indexes, reduce: <<>> do
              acc -> acc <> <<index::16-little>>
            end

          req_bin =
            <<r.erasure_root::b(hash)>> <>
              <<r.segment_index::16-little>> <>
              e(length(r.shard_indexes)) <>
              indexes

          acc <> req_bin
      end

    protocol_id = if(with_justification, do: 140, else: 139)

    send(pid, protocol_id, message)
  end

  @impl true
  def send_work_package(pid, wp, core_index, extrinsics) do
    messages = [t(core_index) <> e(wp), e(extrinsics)]
    send(pid, 133, messages)
  end

  @impl true
  def send_work_package_bundle(pid, bundle, core_index, segment_roots) do
    messages = [t(core_index) <> e(segment_roots), bundle]
    send(pid, 134, messages)
  end

  @impl true
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
        %ConnectionState{up_streams: up_streams} = state
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
        {:ok, stream} = :quicer.start_stream(state.connection, default_stream_opts())
        Logger.stream(:debug, "Created new UP stream", stream, protocol_id)

        state = put_in(state.up_streams[protocol_id], %{stream: stream})
        state = put_in(state.up_stream_data[stream], %{protocol_id: protocol_id, buffer: <<>>})

        log(:debug, "Sending block announcement: hash=#{inspect(hash)}, slot=#{slot}")
        {:ok, _} = :quicer.send(stream, <<protocol_id::8>>, send_flag(:none))
        {:ok, _} = :quicer.send(stream, encode_message(message), send_flag(:none))

        {:noreply, state}
    end
  end

  def handle_call({:send, protocol_id, message}, from, %ConnectionState{} = state)
      when is_binary(message) do
    handle_call({:send, protocol_id, [message]}, from, state)
  end

  def handle_call({:send, protocol_id, messages}, from, %ConnectionState{} = state)
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

    {:noreply, %ConnectionState{state | pending_responses: new_pending}}
  end

  def handle_data(data, stream, props, %ConnectionState{} = state) do
    state_ =
      case Map.get(state.pending_responses, stream) do
        nil ->
          # This stream is not in pending_responses, that means that this is not a CE stream initiated by the client
          # 1. unsolicited data from somewhere, not to handle
          # 2. could be an up_stream, but we expect up stream to be used for cast, not waiting for response

          # so finally we just ignore it
          Logger.stream(:debug, "ignoring unsolicited data from stream", stream)
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
