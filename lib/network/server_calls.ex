defmodule Network.ServerCalls do
  alias System.Audit.AuditAnnouncement
  alias Block.Extrinsic.WorkPackage
  alias Block.Extrinsic.Guarantee
  alias Block.Extrinsic.{Assurance, Disputes.Judgement, TicketProof}
  require Logger
  use Codec.Encoder

  def log(message), do: Logger.log(:info, "[QUIC_SERVER_CALLS] #{message}")

  def call(protocol_id, [single_message]) do
    call(protocol_id, single_message)
  end

  def call(128, <<hash::32, direction::8, max_blocks::32>> = _message) do
    log("Sending #{max_blocks} blocks in direction #{direction}")
    {:ok, blocks} = Jamixir.NodeAPI.get_blocks(hash, direction, max_blocks)
    blocks_bin = for b <- blocks, do: Encodable.encode(b)
    Enum.join(blocks_bin)
  end

  def call(135, message) do
    log("Received guarantee")
    {g, <<>>} = Guarantee.decode(message)
    :ok = Jamixir.NodeAPI.save_guarantee(g)
    <<>>
  end

  def call(136, message) do
    log("Requesting work report")

    case Jamixir.NodeAPI.get_work_report(message) do
      {:ok, report} -> e(report)
      _ -> <<>>
    end
  end

  use Sizes

  def call(141, <<hash::b(hash), bitfield::b(bitfield), signature::b(signature)>>) do
    log("Received assurance")

    assurance = %Assurance{hash: hash, bitfield: bitfield, signature: signature}

    :ok = Jamixir.NodeAPI.save_assurance(assurance)
    <<>>
  end

  def call(142, <<service_id::service(), hash::b(hash), length::32-little>> = _message) do
    log("Receiving Preimage")
    :ok = Jamixir.NodeAPI.receive_preimage(service_id, hash, length)
    <<>>
  end

  def call(143, hash) do
    log("Received preimage request")

    case Jamixir.NodeAPI.get_preimage(hash) do
      {:ok, preimage} -> preimage
      _ -> <<>>
    end
  end

  def call(131, m), do: process_ticket_message(:proxy, m)
  def call(132, m), do: process_ticket_message(:validator, m)

  def call(133, [wp_and_core, extrinsic]) do
    <<core_index::16-little, rest::binary>> = wp_and_core
    {wp, _} = WorkPackage.decode(rest)
    log("Received work package for service #{wp.service} core #{core_index}")
    :ok = Jamixir.NodeAPI.save_work_package(wp, core_index, extrinsic)
    <<>>
  end

  def call(134, [segments_and_core, bundle]) do
    <<core_index::16-little, segments_bin::binary>> = segments_and_core
    {segments, _} = VariableSize.decode(segments_bin, :map, @hash_size, @hash_size)
    {:ok, {hash, sign}} = Jamixir.NodeAPI.save_work_package_bundle(bundle, core_index, segments)

    hash <> sign
  end

  def call(144, [message1, evidence_bin]) do
    log("Received audit announcement")
    <<header_hash::b(hash), tranche::8, announcements::binary>> = message1

    {announcements, signature} =
      VariableSize.decode(announcements, :list_of_tuples, 2, @hash_size)

    announcements =
      for {<<core::m(core_index)>>, hash} <- announcements do
        {core, hash}
      end

    audit_announcement = %AuditAnnouncement{
      tranche: tranche,
      announcements: announcements,
      header_hash: header_hash,
      signature: signature,
      evidence: evidence_bin
    }

    # {audit_announcement, <<>>} = AuditAnnouncement.decode(bin)
    :ok = Jamixir.NodeAPI.save_audit(audit_announcement)
    <<>>
  end

  def call(
        145,
        <<epoch_index::m(epoch_index), validator_index::m(validator_index), vote::8,
          hash::b(hash), signature::b(signature)>>
      ) do
    judgement = %Judgement{
      vote: vote,
      validator_index: validator_index,
      signature: signature
    }

    :ok = Jamixir.NodeAPI.save_judgement(epoch_index, hash, judgement)
    <<>>
  end

  def call(0, _message) do
    log("Processing block announcement")
    # TODO: Implement block processing
    :ok
  end

  def call(protocol_id, messages) when is_list(messages) do
    Logger.warning(
      "Received unknown message #{protocol_id} on server. Ignoring #{inspect(messages)}}"
    )

    IO.iodata_to_binary(messages)
  end

  def call(protocol_id, message) do
    Logger.warning(
      "Received unknown message #{protocol_id} on server. Ignoring #{inspect(message)} of size #{byte_size(message)}"
    )

    message
  end

  defp process_ticket_message(
         mode,
         <<epoch::m(epoch), attempt::8, vrf_proof::b(bandersnatch_proof)>>
       ),
       do: process_ticket(mode, epoch, attempt, vrf_proof)

  defp process_ticket(mode, epoch, attempt, vrf_proof) do
    log("Processing #{mode} ticket")
    ticket = %TicketProof{attempt: attempt, signature: vrf_proof}
    :ok = Jamixir.NodeAPI.process_ticket(mode, epoch, ticket)
    <<>>
  end
end
