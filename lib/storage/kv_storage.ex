defmodule KVStorage do
  @cache_table :kv_cache
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
      [{^key, value}] ->
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
    :ets.delete(@cache_table, key)
    PersistStorage.delete(key)
    :ok
  end

  def remove_all do
    :ets.delete_all_objects(@cache_table)
    :ets.insert(@cache_meta, {:size, 0})
    PersistStorage.clear()
  end

  # --- Cache management ---

  defp init_cache do
    if :ets.whereis(@cache_table) == :undefined do
      :ets.new(@cache_table, [:set, :public, :named_table, {:read_concurrency, true}])
      :ets.new(@cache_meta, [:set, :public, :named_table])
      :ets.insert(@cache_meta, {:size, 0})
    end
  end

  defp cache_put(key, value) do
    is_new = :ets.insert_new(@cache_table, {key, value})

    if is_new do
      new_size = :ets.update_counter(@cache_meta, :size, 1)
      maybe_evict(new_size)
    else
      :ets.insert(@cache_table, {key, value})
    end
  end

  defp maybe_evict(current_size) do
    max_entries = max_cache_entries()

    if current_size > max_entries do
      # Evict ~20% of entries (random eviction - simple and fast)
      evict_count = div(max_entries, 5)
      evict_random(evict_count)
    end
  end

  defp evict_random(count) do
    do_evict(:ets.first(@cache_table), count, 0)
  end

  defp do_evict(:"$end_of_table", _count, deleted), do: update_size(-deleted)
  defp do_evict(_key, count, deleted) when deleted >= count, do: update_size(-deleted)

  defp do_evict(key, count, deleted) do
    next_key = :ets.next(@cache_table, key)
    :ets.delete(@cache_table, key)
    do_evict(next_key, count, deleted + 1)
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
