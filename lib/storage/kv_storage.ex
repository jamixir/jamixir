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
    # Insert everything without eviction
    Enum.each(map, fn {k, v} ->
      cache_put(k, v, false)
    end)

    # Evict only the excess
    excess = size() - max_cache_entries()

    if excess > 0 do
      evict_n(excess)
    end

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

  defp cache_put(key, value, allow_evict? \\ true) do
    case :ets.lookup(@cache_table, key) do
      [{^key, _seq, _}] ->
        :ets.update_element(@cache_table, key, {3, value})

      [] ->
        seq = :ets.update_counter(@cache_meta, :seq, 1)
        :ets.insert(@cache_table, {key, seq, value})
        :ets.insert(@cache_order, {seq, key})
        new_size = :ets.update_counter(@cache_meta, :size, 1)
        if allow_evict?, do: maybe_evict_one(new_size)
    end
  end

  defp size do
    :ets.lookup_element(@cache_meta, :size, 2)
  end

  defp evict_n(n) do
    Enum.each(1..n, fn _ -> evict_one() end)
  end

  # Incremental eviction - evict ONE oldest entry per insert when over limit
  # This spreads the cost evenly, avoiding latency spikes
  defp maybe_evict_one(current_size) do
    max_entries = max_cache_entries()

    if current_size > max_entries do
      evict_one()
    end
  end

  # Evict the single oldest entry - O(1) operations only
  defp evict_one do
    # Get the oldest entry from ordered_set (first key is smallest/oldest seq)
    case :ets.first(@cache_order) do
      :"$end_of_table" ->
        :ok

      oldest_seq ->
        # Get the key for this seq
        case :ets.lookup(@cache_order, oldest_seq) do
          [{^oldest_seq, key}] ->
            # Delete from both tables - O(1) each
            :ets.delete(@cache_order, oldest_seq)
            :ets.delete(@cache_table, key)
            update_size(-1)

          [] ->
            :ok
        end
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
