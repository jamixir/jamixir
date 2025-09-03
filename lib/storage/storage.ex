defmodule Storage do
  alias Block.Extrinsic.TicketProof
  alias Codec.VariableSize
  alias Block.Extrinsic.WorkPackage
  alias Block.Header
  alias Codec.State.Trie
  alias System.State
  alias Util.Hash
  import Codec.Encoder
  import Util.Hex, only: [b16: 1]
  use StoragePrefix

  @log_context "[STORAGE]"
  use Util.Logger

  @latest_timeslot "latest_timeslot"

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

  def put(headers) when is_list(headers), do: put_headers(headers)

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

  def put(%Block{} = b, %State{} = s), do: put(b.header, s)

  def put(%Header{} = h, %State{} = s) do
    put(h)
    put(h(e(h)), s)
  end

  def put(header_hash, %State{} = state) do
    log(:debug, "Storing state for header #{b16(header_hash)}")
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

  def get_latest_header do
    case KVStorage.get(@latest_timeslot) do
      nil ->
        nil

      timeslot ->
        case KVStorage.get(@p_timeslot <> t(timeslot)) do
          nil -> nil
          header -> {timeslot, header}
        end
    end
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

  # Private Functions

  defp encodable?(data), do: not is_nil(Encodable.impl_for(data))

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
