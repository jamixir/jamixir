defmodule Storage do
  alias Block.Extrinsic.Preimage
  alias Block.Extrinsic.Guarantee
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Block.Extrinsic.Disputes.Judgement
  alias Block.Extrinsic.Assurance
  alias Jamixir.SqlStorage
  alias Block.Extrinsic.TicketProof
  alias Codec.VariableSize
  alias Block.Extrinsic.WorkPackage
  alias Block.Header
  alias Codec.State.Trie
  alias System.State
  alias Storage.AvailabilityRecord
  alias Storage.GuaranteeRecord
  alias Storage.PreimageMetadataRecord
  alias Util.Hash
  import Codec.Encoder
  import Util.Hex, only: [b16: 1]
  use StoragePrefix

  @log_context "[STORAGE]"
  use Util.Logger

  @latest_timeslot "latest_timeslot"
  @canonical_tip "canonical_tip"
  def latest_timeslot, do: @latest_timeslot

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(opts) do
    case KVStorage.start_link(opts) do
      {:ok, pid} ->
        # Initialize with zero header
        KVStorage.put(%{Hash.zero() => nil, "t:0" => nil, :latest_timeslot => 0})
        {:ok, pid}

      error ->
        error
    end
  end

  def put(%Block{} = block) do
    {:ok, header_hash} = put(block.header)

    key = @p_block <> header_hash

    {:ok, _} = KVStorage.put(%{key => Encodable.encode(block)})
    {:ok, _} = SqlStorage.save_block(header_hash, block.header.parent_hash, block.header.timeslot)

    {:ok, key}
  end

  def put(%Header{} = header) do
    hash = h(e(header))

    KVStorage.put(%{
      hash => header,
      (@p_child <> header.parent_hash) => hash,
      (@p_timeslot <> t(header.timeslot)) => header,
      @latest_timeslot => header.timeslot
    })

    {:ok, hash}
  end

  def put(%Guarantee{} = guarantee) do
    wr = guarantee.work_report
    encoded_wr = e(wr)
    wr_hash = h(encoded_wr)

    put(@p_work_report <> wr_hash, encoded_wr)
    SqlStorage.save(guarantee, wr_hash)
  end

  def put(headers) when is_list(headers), do: put_headers(headers)

  def put(%Assurance{} = assurance) do
    SqlStorage.save(assurance)
  end

  def put(%Preimage{} = preimage) do
    hash = h(preimage.blob)

    SqlStorage.save(%PreimageMetadataRecord{
      service_id: preimage.service,
      hash: hash,
      length: byte_size(preimage.blob)
    })

    put(@p_preimage <> hash, preimage.blob)
  end

  def put(%PreimageMetadataRecord{} = preimage_metadata) do
    SqlStorage.save(preimage_metadata)
  end

  def put(%AvailabilityRecord{} = availability_record) do
    SqlStorage.save(availability_record)
  end

  def put(object) when is_struct(object) do
    case encodable?(object) do
      true -> KVStorage.put(h(e(object)), object)
      false -> raise "Struct does not implement Encodable protocol"
    end
  end

  def put(blob) when is_binary(blob), do: KVStorage.put(h(blob), blob)

  def put(items) when is_list(items) do
    # First convert items to {key, value} pairs, stopping if we hit an error
    case Enum.reduce_while(items, [], fn item, acc ->
           case prepare_entry(item) do
             {:ok, entry} -> {:cont, [entry | acc]}
             {:error, reason} -> {:halt, {:error, reason}}
           end
         end) do
      {:error, reason} ->
        {:error, reason}

      entries ->
        KVStorage.put(entries)
    end
  end

  def put(%Block{} = b, %State{} = s) do
    # Store the full block first (this also stores the header and creates child relationship)
    put(b)
    # Then store the state for this block
    put(h(e(b.header)), s)
  end

  def put(%Header{} = h, %State{} = s) do
    put(h)
    put(h(e(h)), s)
  end

  def put(header_hash, %State{} = state) do
    debug("Storing state for header #{b16(header_hash)}")
    serial_state = Trie.serialize(state)
    state_root = Trie.state_root(serial_state)

    KVStorage.put(%{
      (@p_state <> header_hash <> "t") => serial_state,
      (@p_state <> header_hash) => state,
      (@p_state_root <> header_hash) => state_root
    })

    state_root
  end

  def put(%WorkPackage{} = work_package, core) do
    key = <<@p_wp, core::m(core_index)>>
    KVStorage.put(%{key => e(work_package)})
  end

  def put(epoch, %TicketProof{} = ticket) do
    key = @p_ticket <> <<epoch::little-16>>
    KVStorage.put(key, e(vs(get_tickets(epoch) ++ [ticket])))
  end

  def put(key, value), do: KVStorage.put(key, value)

  def put(%Judgement{} = judgement, work_report_hash, epoch) do
    SqlStorage.save(judgement, work_report_hash, epoch)
  end

  defp prepare_entry({key, value}), do: {:ok, {key, value}}

  defp prepare_entry(blob) when is_binary(blob) do
    {:ok, {h(blob), blob}}
  end

  defp prepare_entry(struct) when is_struct(struct) do
    if encodable?(struct) do
      {:ok, {h(e(struct)), struct}}
    else
      {:error, "Struct #{struct.__struct__} does not implement Encodable protocol"}
    end
  end

  def get(hash), do: KVStorage.get(hash)

  def remove(key), do: KVStorage.remove(key)
  def remove_all, do: KVStorage.remove_all()

  def get_availability(%WorkReport{} = work_report) do
    hash = work_report.specification.work_package_hash
    SqlStorage.get(AvailabilityRecord, hash)
  end

  def get_latest_timeslot do
    KVStorage.get(@latest_timeslot)
  end

  def get_canonical_header do
    case get_canonical_tip() do
      nil -> nil
      tip_hash ->
        case get(tip_hash) do
          nil -> nil
          header -> {header.timeslot, header}
        end
    end
  end

  def get_canonical_state_root do
    tip = get_canonical_tip()
    Storage.get_state_root(tip)
  end

  def get_block(header_hash) do
    case KVStorage.get(@p_block <> header_hash) do
      nil ->
        nil

      bin ->
        {block, _} = Block.decode(bin)
        block
    end
  end

  def get_preimage(hash) do
    case get("#{@p_preimage}#{hash}") do
      nil ->
        {:error, :not_found}

      blob ->
        {:ok, blob}
    end
  end

  def get_work_package(core) do
    case KVStorage.get(<<@p_wp, core::m(core_index)>>) do
      nil ->
        nil

      bin ->
        {wp, _} = WorkPackage.decode(bin)
        wp
    end
  end

  def get_state(%Header{} = header), do: get_state(h(e(header)))

  def get_state(header_hash) do
    KVStorage.get(@p_state <> header_hash)
  end

  def get_state_trie(header_hash) do
    KVStorage.get(@p_state <> header_hash <> "t")
  end

  def get_state(header_hash, key) do
    KVStorage.get(@p_state <> header_hash <> to_string(key))
  end

  def get_state_root(header_hash), do: KVStorage.get(@p_state_root <> header_hash)

  def has_block?(header_hash) when is_binary(header_hash) do
    case get(header_hash) do
      nil -> false
      _header -> true
    end
  end

  def has_parent?(%Header{} = header) do
    case header.parent_hash do
      nil -> true
      parent_hash -> has_block?(parent_hash)
    end
  end

  def get_canonical_root(header_hash) do
    SqlStorage.get_canonical_root(header_hash)
  end

  def get_heaviest_chain_tip_from_canonical_root(canonical_root) do
    SqlStorage.get_heaviest_chain_tip_from_canonical_root(canonical_root)
  end

  def mark_applied(header_hash) do
    SqlStorage.mark_applied(header_hash)
    set_canonical_tip(header_hash)
  end

  def unmark_between(start_hash, end_hash) do
    SqlStorage.unmark_between(start_hash, end_hash)
  end

  def set_canonical_tip(header_hash) do
    KVStorage.put(@canonical_tip, header_hash)
  end

  def get_canonical_tip do
    KVStorage.get(@canonical_tip)
  end

  def get_segments_root(hash), do: KVStorage.get(@p_segments_root <> hash)
  def put_segments_root(wp_hash, root), do: KVStorage.put(@p_segments_root <> wp_hash, root)

  def get_next_block(header_hash) do
    KVStorage.get(@p_child <> header_hash)
  end

  def get_segment(merkle_root, segment_index) do
    KVStorage.get(@p_segment <> merkle_root <> <<segment_index::little-32>>)
  end

  def put_segment(merkle_root, segment_index, segment) do
    KVStorage.put(@p_segment <> merkle_root <> <<segment_index::little-32>>, segment)
  end

  def put_segment_shard(erasure_root, shard_index, segment_index, segment_shard) do
    KVStorage.put(
      @p_segment_shard <>
        erasure_root <>
        <<shard_index::m(validator_index)>> <>
        <<segment_index::little-32>>,
      segment_shard
    )
  end

  @spec put_bundle_shard(Hash.t(), non_neg_integer(), binary()) ::
          {:ok, binary()} | {:error, term()}
  def put_bundle_shard(wp_hash, shard_index, bundle_shard) do
    KVStorage.put(
      @p_bundle_shard <> wp_hash <> <<shard_index::m(validator_index)>>,
      bundle_shard
    )
  end

  def get_segment_shard(erasure_root, shard_index, segment_index) do
    KVStorage.get(
      @p_segment_shard <>
        erasure_root <>
        <<shard_index::m(validator_index)>> <>
        <<segment_index::little-32>>
    )
  end

  def get_bundle_shard(wp_hash, shard_index) do
    KVStorage.get(@p_bundle_shard <> wp_hash <> <<shard_index::m(validator_index)>>)
  end

  def get_segment_core(merkle_root) do
    KVStorage.get(@p_segment_core <> merkle_root)
  end

  def set_segment_core(merkle_root, core_index) do
    KVStorage.put(@p_segment_core <> merkle_root, core_index)
  end

  def get_tickets(epoch) do
    case KVStorage.get(@p_ticket <> <<epoch::little-16>>) do
      nil -> []
      tickets_bin -> VariableSize.decode(tickets_bin, TicketProof) |> elem(0)
    end
  end

  def get_assurances do
    SqlStorage.get_all(Assurance)
  end

  def get_assurances(hash) do
    SqlStorage.get_all(Assurance, hash)
  end

  def get_assurance(hash, validator_index) do
    SqlStorage.get(Assurance, [hash, validator_index])
  end

  def get_work_report(hash) do
    case KVStorage.get(@p_work_report <> hash) do
      nil ->
        nil

      work_report_bin ->
        {work_report, _} = WorkReport.decode(work_report_bin)
        work_report
    end
  end

  def mark_guarantee_included(guarantee_work_report_hashes, header_hash) do
    SqlStorage.mark_included(guarantee_work_report_hashes, header_hash)
  end

  def mark_preimage_included(hash, service_id) do
    SqlStorage.mark_preimage_included(hash, service_id)
  end

  def get_judgements(epoch) do
    SqlStorage.get_all(Judgement, epoch)
  end

  def get_guarantees(status) do
    SqlStorage.get_all(Guarantee, status)
    |> Enum.map(&attach_work_report/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.group_by(& &1.work_report.core_index)
    |> Enum.map(fn {_core_index, guarantees} ->
      # for now we just take the first guarantee for each core
      #  we may want to use different strategy in the future, for example, take the guarantee with the latest timeslot
      hd(guarantees)
    end)
  end

  def get_preimages(status) do
    for r <- SqlStorage.get_all(Preimage, status),
        blob = Storage.get(@p_preimage <> r.hash),
        r.length == byte_size(blob),
        h(blob) == r.hash do
      %Preimage{service: r.service_id, blob: blob}
    end
  end

  # Private Functions

  defp encodable?(data), do: not is_nil(Encodable.impl_for(data))

  defp attach_work_report(%GuaranteeRecord{} = rec) do
    case get_work_report(rec.work_report_hash) do
      nil ->
        # should never happen as we save guarantee recordes and their work report atomically (CE-135)
        # the split (between guarantee and it's work report) is
        # just a DB design choise, in order to allow SQL querying over guarantees
        nil

      work_report ->
        %Guarantee{
          work_report: work_report,
          timeslot: rec.timeslot,
          credentials: Guarantee.decode_credentials(rec.credentials)
        }
    end
  end

  @spec put_headers(list(Header.t())) :: {:ok, list(String.t())}
  defp put_headers(headers) do
    if Enum.all?(headers, &is_struct(&1, Header)) do
      latest_timeslot = Enum.max_by(headers, & &1.timeslot, fn -> 0 end).timeslot

      map =
        Enum.reduce(headers, %{}, fn header, acc ->
          acc
          |> Map.put(h(e(header)), header)
          |> Map.put(@p_timeslot <> t(header.timeslot), header)
          |> Map.put(@latest_timeslot, latest_timeslot)
        end)

      KVStorage.put(map)
    else
      {:error, "All items must be Header structs"}
    end
  end

  def stop do
    :mnesia.stop()

    if pid = Process.whereis(PersistStorage) do
      GenServer.stop(pid)
    end

    if pid = Process.whereis(:cubdb) do
      GenServer.stop(pid)
    end
  end
end
