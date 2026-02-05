defmodule Network.ServerCalls do
  alias Block.Extrinsic.{Assurance, Disputes.Judgement, Guarantee, TicketProof}
  alias Block.Extrinsic.{WorkPackage, WorkPackageBundle}
  alias Block.Header
  alias Codec.VariableSize
  alias Network.Types.SegmentShardsRequest
  alias System.Audit.AuditAnnouncement
  import Codec.Encoder
  use Sizes
  import RangeMacros
  import Util.Hex, only: [b16: 1]

  @behaviour Network.ServerCallsBehaviour
  @callback call(protocol_id :: integer(), message :: binary() | [binary()]) :: any

  @log_context "[QUIC_SERVER_CALLS]"
  use Util.Logger

  def call(protocol_id, [single_message]) do
    call(protocol_id, single_message)
  end

  def call(128, <<hash::b(hash), direction::8, max_blocks::32-little>> = _message) do
    dir = if direction == 0, do: :ascending, else: :descending
    {:ok, blocks} = Jamixir.NodeAPI.get_blocks(hash, dir, max_blocks)
    blocks_bin = for b <- blocks, do: Encodable.encode(b)
    Enum.join(blocks_bin)
  end

  def call(
        129,
        <<block_hash::b(hash), start_key::binary-size(31), end_key::binary-size(31),
          max_size::32-little>>
      ) do
    log("Sending state")
    {:ok, {state_trie, bounderies}} = Jamixir.NodeAPI.get_state_trie(block_hash)

    # First filter the state trie to get the relevant keys
    result_map =
      Map.filter(state_trie, fn {k, _v} ->
        k >= start_key && k <= end_key
      end)

    # Then, we need to limit the size of the result_map to max_size
    {result_map, _} =
      Enum.reduce_while(result_map, {%{}, 0}, fn {k, v}, {map_acc, byte_count} ->
        if byte_count + byte_size(v) > max_size do
          {:halt, {map_acc, byte_count}}
        else
          {:cont, {Map.put(map_acc, k, v), byte_count + byte_size(v)}}
        end
      end)

    # Convert the result_map to a binary format
    trie_bin =
      for {<<k::binary-size(31)>>, v} <- result_map, reduce: <<>> do
        acc -> acc <> k <> e(vs(v))
      end

    [bounderies, trie_bin]
  end

  def call(131, m), do: process_ticket_message(:proxy, m)
  def call(132, m), do: process_ticket_message(:validator, m)

  def call(133, [wp_and_core, extrinsic_bin]) do
    <<core_index::16-little, rest::binary>> = wp_and_core
    {wp, _} = WorkPackage.decode(rest)
    log("Received work package for service #{wp.service} core #{core_index}")

    {_, extrinsics} =
      Enum.reduce_while(WorkPackage.extrinsic_defs(wp), {extrinsic_bin, []}, fn {_, e_size},
                                                                                {bin, extrinsics} ->
        case bin do
          <<>> ->
            {:halt, {<<>>, extrinsics}}

          <<e::binary-size(e_size), rest::binary>> ->
            {:cont, {rest, extrinsics ++ [e]}}
        end
      end)

    :ok = Jamixir.NodeAPI.save_work_package(wp, core_index, extrinsics)
    <<>>
  end

  def call(134, [segments_and_core, bundle_bin]) do
    <<core_index::16-little, segments_bin::binary>> = segments_and_core
    {lookup_dict, _} = VariableSize.decode(segments_bin, :map, @hash_size, @hash_size)
    {bundle, _} = WorkPackageBundle.decode(bundle_bin)

    {:ok, {hash, sign}} =
      Jamixir.NodeAPI.save_work_package_bundle(bundle, core_index, lookup_dict)

    hash <> sign
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

  def call(137, <<erasure_root::binary-size(@hash_size), shard_index::16-little>>) do
    log("Requesting Work Report Shard")

    case Jamixir.NodeAPI.get_work_package_shard(erasure_root, shard_index) do
      {:ok, {bundle_shard, segments, justification}} ->
        [bundle_shard, segments, justification]

      _ ->
        [<<>>, [], []]
    end
  end

  def call(138, <<erasure_root::binary-size(@hash_size), segment_index::16-little>>) do
    log("Requesting segment")

    case Jamixir.NodeAPI.get_work_package_shard(erasure_root, segment_index) do
      {:ok, {bundle_shard, _, justification}} ->
        [bundle_shard, justification]

      _ ->
        IO.puts("Received segment 2")
        <<>>
    end
  end

  def call(139, requests_bin) do
    log("Requesting segment shards")

    for r <- decode_requests(requests_bin, []) do
      log("Requesting segment shards for erasure root #{inspect(r.erasure_root)}")

      {:ok, shards} =
        Jamixir.NodeAPI.get_segment_shards(r.erasure_root, r.shard_index, r.segment_indexes)

      shards
    end
    |> List.flatten()
    |> Enum.join(<<>>)
  end

  def call(140, requests_bin) do
    log("Requesting segment shards with justification")

    {shards_bin, justifications} =
      for r <- decode_requests(requests_bin, []), reduce: {<<>>, []} do
        {shards_bin, justifications_acc} ->
          log("Requesting segment shards for erasure root #{inspect(r.erasure_root)}")

          {:ok, shards} =
            Jamixir.NodeAPI.get_segment_shards(r.erasure_root, r.shard_index, r.segment_indexes)

          justifications =
            for segment_index <- r.segment_indexes do
              {:ok, justification} =
                Jamixir.NodeAPI.get_justification(r.erasure_root, r.shard_index, segment_index)

              justification
            end

          {shards_bin <> Enum.join(shards, <<>>), justifications_acc ++ justifications}
      end

    [shards_bin | justifications]
  end

  def call(141, <<hash::b(hash), bitfield::b(bitfield), signature::b(signature)>>) do
    log("🛡️ Received assurance for parent block #{b16(hash)}")

    assurance = %Assurance{hash: hash, bitfield: bitfield, signature: signature}

    {:ok, _} = Jamixir.NodeAPI.save_assurance(assurance)
    <<>>
  end

  def call(142, <<service_id::service(), hash::b(hash), length::32-little>> = _message) do
    log("Receiving Preimage announcement")
    :ok = Jamixir.NodeAPI.receive_preimage(service_id, hash, length)
    <<>>
  end

  def call(143, hash) do
    log("Received preimage request")

    case Jamixir.NodeAPI.get_preimage(hash) do
      {:ok, blob} -> blob
      _ -> <<>>
    end
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

  def call(0, message) do
    debug("Processing block announcement")
    {header, rest} = Header.decode(message)
    <<hash::b(hash), timeslot::m(timeslot)>> = rest
    :ok = Jamixir.NodeAPI.announce_block(header, hash, timeslot)
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

    message <> :erlang.term_to_binary(self())
  end

  import Codec.Decoder
  defp decode_requests(<<>>, acc), do: Enum.reverse(acc)

  defp decode_requests(bin, acc) do
    <<erasure_root::binary-size(@hash_size), rest::binary>> = bin
    <<shard_index::16-little, rest::binary>> = rest
    {indexes_count, rest} = de_i(rest)

    {segment_indexes, rest} =
      Enum.reduce(from_0_to(indexes_count), {[], rest}, fn _, {acc, rest} ->
        <<value::16-little, r::binary>> = rest
        {acc ++ [value], r}
      end)

    request = %SegmentShardsRequest{
      erasure_root: erasure_root,
      shard_index: shard_index,
      segment_indexes: segment_indexes
    }

    # Continue decoding the rest
    decode_requests(rest, [request | acc])
  end

  defp process_ticket_message(
         mode,
         <<epoch::m(epoch), attempt::8, vrf_proof::b(bandersnatch_proof)>>
       ),
       do: process_ticket(mode, epoch, attempt, vrf_proof)

  defp process_ticket(mode, epoch, attempt, vrf_proof) do
    debug("Processing #{mode} ticket")
    ticket = %TicketProof{attempt: attempt, signature: vrf_proof}
    :ok = Jamixir.NodeAPI.process_ticket(mode, epoch, ticket)
    <<>>
  end
end
