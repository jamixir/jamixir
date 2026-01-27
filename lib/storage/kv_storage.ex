defmodule KVStorage do
  @cache_table :kv_cache
  @cache_order :kv_cache_order
  @cache_meta :kv_cache_meta
  # Max entries before eviction (configurable via Jamixir.config()[:kv_cache_max_entries])
  @default_max_entries 100_000

  def start_link(opts \\ []) do
    init_cache()

    with {:ok, _pid} <- PersistStorage.start_link(opts) do
      {:ok, self()}
    end
  end

  def put(key, value) do
    cache_put(key, value)
    PersistStorage.put(key, value)
    {:ok, key}
  end

  def put(map) when is_map(map) do
    Enum.each(map, fn {k, v} -> cache_put(k, v) end)
    PersistStorage.put(map)
    {:ok, Map.keys(map)}
  end

  def get(key) do
    case :ets.lookup(@cache_table, key) do
      [{^key, _seq, value}] ->
        value

      [] ->
        # Cache miss - fetch from disk
        case PersistStorage.get(key) do
          nil ->
            nil

          value ->
            cache_put(key, value)
            value
        end
    end
  end

  def remove(key) do
    case :ets.lookup(@cache_table, key) do
      [{^key, seq, _value}] ->
        :ets.delete(@cache_table, key)
        :ets.delete(@cache_order, seq)
        update_size(-1)

      [] ->
        :ok
    end

    PersistStorage.delete(key)
    :ok
  end

  def remove_all do
    :ets.delete_all_objects(@cache_table)
    :ets.delete_all_objects(@cache_order)
    :ets.insert(@cache_meta, {:size, 0})
    :ets.insert(@cache_meta, {:seq, 0})
    PersistStorage.clear()
  end

  # --- Cache management ---

  defp init_cache do
    if :ets.whereis(@cache_table) == :undefined do
      # Main cache: key -> {key, seq, value}
      :ets.new(@cache_table, [:set, :public, :named_table, {:read_concurrency, true}])
      # Order tracking: seq -> key (ordered_set for FIFO eviction)
      :ets.new(@cache_order, [:ordered_set, :public, :named_table])
      :ets.new(@cache_meta, [:set, :public, :named_table])
      :ets.insert(@cache_meta, {:size, 0})
      :ets.insert(@cache_meta, {:seq, 0})
    end
  end

  defp cache_put(key, value) do
    case :ets.lookup(@cache_table, key) do
      [{^key, _old_seq, _old_value}] ->
        # Update existing - keep same seq (don't change order)
        :ets.update_element(@cache_table, key, {3, value})

      [] ->
        # New entry - assign sequence number
        seq = :ets.update_counter(@cache_meta, :seq, 1)
        :ets.insert(@cache_table, {key, seq, value})
        :ets.insert(@cache_order, {seq, key})
        new_size = :ets.update_counter(@cache_meta, :size, 1)
        maybe_evict(new_size)
    end
  end

  defp maybe_evict(current_size) do
    max_entries = max_cache_entries()

    if current_size > max_entries do
      # Evict oldest 20% (FIFO)
      evict_count = div(max_entries, 5)
      evict_oldest(evict_count)
    end
  end

  defp evict_oldest(count) do
    # Find the cutoff sequence number (oldest N entries)
    case :ets.select(@cache_order, [{{:"$1", :_}, [], [:"$1"]}], count) do
      {seqs, _continuation} when seqs != [] ->
        max_seq = Enum.max(seqs)

        # Bulk delete from order table: all entries with seq <= max_seq
        deleted_order =
          :ets.select_delete(@cache_order, [{{:"$1", :_}, [{:"=<", :"$1", max_seq}], [true]}])

        # Bulk delete from cache table: all entries with seq <= max_seq
        :ets.select_delete(@cache_table, [{{:_, :"$1", :_}, [{:"=<", :"$1", max_seq}], [true]}])

        update_size(-deleted_order)

      _ ->
        :ok
    end
  end

  defp update_size(delta) do
    :ets.update_counter(@cache_meta, :size, delta)
  end

  defp max_cache_entries do
    case function_exported?(Jamixir, :config, 0) do
      true -> Jamixir.config()[:kv_cache_max_entries] || @default_max_entries
      false -> @default_max_entries
    end
  end
end
