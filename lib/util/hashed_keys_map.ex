defmodule HashedKeysMap do
  import Codec.Encoder
  import Bitwise

  @storage_prefix <<(1 <<< 32) - 1::little-32>>
  @storage_overhead 34
  @preimage_storage_overhead 81
  @hash_key_size 27

  @type t :: %__MODULE__{
          original_map: map(),
          hashed_map: map(),
          octets_in_storage: non_neg_integer()
        }

  defstruct original_map: %{},
            hashed_map: %{},
            octets_in_storage: 0,
            items_in_storage: 0,
            hash_prefix: @storage_prefix

  def new_without_original(map) do
    m = new(map)
    %__MODULE__{m | original_map: %{}}
  end

  def new(map), do: new(map, @storage_prefix)
  def new, do: new(%{})

  def new(map, hash_prefix) when map_size(map) == 0 do
    %__MODULE__{
      original_map: %{},
      hashed_map: %{},
      items_in_storage: 0,
      octets_in_storage: 0,
      hash_prefix: hash_prefix
    }
  end

  def new(map, hash_prefix) do
    Enum.reduce(map, new(%{}, hash_prefix), fn {k, v}, acc ->
      put_in(acc, [k], v)
    end)
  end

  def get(map, key) do
    Map.get(map.hashed_map, hash_key(map.hash_prefix, key))
  end

  def drop(map, keys) do
    # Collect hashed keys and calculate new counts in one pass
    {items_in_storage, octets_in_storage, hashed_keys_to_drop} =
      for key <- keys, reduce: {map.items_in_storage, map.octets_in_storage, []} do
        {items_in_storage, octets_in_storage, hashed_keys_acc} ->
          hashed_key = hash_key(map.hash_prefix, key)

          case Map.get(map.hashed_map, hashed_key) do
            nil ->
              {items_in_storage, octets_in_storage, hashed_keys_acc}

            value ->
              # Formula (9.8) v0.6.7 - Calculate storage cost reduction
              # ai ≡ 2⋅∣al∣ + ∣as∣
              # ao ∈ N2^64 ≡ sum(81 + z) + sum(34 + |x| + |y|),
              {updated_items, updated_octets} =
                case key do
                  # Preimage key removal
                  {_, preimage_length} ->
                    {items_in_storage - 2,
                     octets_in_storage - @preimage_storage_overhead - preimage_length}

                  # Storage key removal
                  k ->
                    {items_in_storage - 1,
                     octets_in_storage - @storage_overhead - byte_size(k) -
                       byte_size(value)}
                end

              {updated_items, updated_octets, [hashed_key | hashed_keys_acc]}
          end
      end

    %__MODULE__{
      original_map: Map.drop(map.original_map, keys),
      hashed_map: Map.drop(map.hashed_map, hashed_keys_to_drop),
      items_in_storage: items_in_storage,
      octets_in_storage: octets_in_storage
    }
  end

  # Access callbacks
  def fetch(%__MODULE__{} = m, key) do
    Map.fetch(m.hashed_map, hash_key(m.hash_prefix, key))
  end

  def get_and_update(%__MODULE__{} = m, key, fun) when is_function(fun) do
    hashed_key = hash_key(m.hash_prefix, key)
    old = Map.get(m.hashed_map, hashed_key)

    case fun.(old) do
      :pop -> get_and_update(m, old, key, :pop)
      {get_val, new_val} -> get_and_update(m, old, key, {get_val, new_val})
      other -> raise "get_and_update expected :pop or {get, new}; got: #{inspect(other)}"
    end
  end

  def get_and_update(%__MODULE__{} = m, old, key, :pop) do
    {old, drop(m, [key])}
  end

  def get_and_update(%__MODULE__{} = m, old, key, {get_val, new_val}) do
    hashed_key = hash_key(m.hash_prefix, key)

    # Calculate new storage counts based on key type and operation
    {updated_items_count, updated_octets_size} =
      case key do
        # Preimage storage key: {hash, length}
        {_, preimage_length} ->
          case old do
            # New preimage entry
            nil ->
              {m.items_in_storage + 2,
               m.octets_in_storage + @preimage_storage_overhead + preimage_length}

            # Update existing preimage
            _ ->
              {m.items_in_storage, m.octets_in_storage}
          end

        # Storage key: binary
        _ ->
          case old do
            nil ->
              # New storage entry: +1 item, +overhead + key_size + value_size
              {m.items_in_storage + 1,
               m.octets_in_storage + @storage_overhead + byte_size(key) +
                 byte_size(new_val)}

            old_val ->
              # Update existing storage: same item count, adjust size for value change
              {
                m.items_in_storage,
                m.octets_in_storage + byte_size(new_val) - byte_size(old_val)
              }
          end
      end

    # Update both maps
    new_struct = %__MODULE__{
      original_map: Map.put(m.original_map, key, new_val),
      hashed_map: Map.put(m.hashed_map, hashed_key, new_val),
      items_in_storage: updated_items_count,
      octets_in_storage: updated_octets_size
    }

    {get_val, new_struct}
  end

  def pop(%__MODULE__{} = m, key) do
    val = Map.get(m.hashed_map, hash_key(m.hash_prefix, key))

    {val, drop(m, [key])}
  end

  def has_key?(map, key), do: Map.has_key?(map.hashed_map, hash_key(map.hash_prefix, key))


  defp hash_key(_, {hash, length}), do: hash_key({hash, length})

  # "Regular" storage key: prefix + key -> hash(prefix + key)
  defp hash_key(prefix, key) do
    <<hashed_key::binary-size(@hash_key_size), _::binary>> = h(prefix <> key)
    hashed_key
  end

  # Preimage storage key: {hash, length} -> hash(length + hash)
  defp hash_key({hash, length}) do
    key = <<length::32-little>> <> hash
    <<hashed_key::binary-size(@hash_key_size), _::binary>> = h(key)
    hashed_key
  end

  # Direct key hashing
  defp hash_key(key) do
    <<hashed_key::binary-size(@hash_key_size), _::binary>> = h(key)
    hashed_key
  end
end

defimpl Enumerable, for: HashedKeysMap do
  # Enumerate only the original keys
  @impl true
  def reduce(%HashedKeysMap{original_map: map}, acc, fun) do
    keys = :maps.keys(map)
    Enumerable.List.reduce(keys, acc, fun)
  end

  @impl true
  def member?(%HashedKeysMap{original_map: map}, key) do
    {:ok, Map.has_key?(map, key)}
  end

  @impl true
  def count(%HashedKeysMap{original_map: map}) do
    {:ok, map_size(map)}
  end

  # Slicing not optimized; fall back
  @impl true
  def slice(_), do: {:error, __MODULE__}
end
