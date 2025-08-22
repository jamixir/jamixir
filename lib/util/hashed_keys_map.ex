defmodule HashedKeysMap do
  import Codec.Encoder
  import Bitwise

  @storage_prefix <<(1 <<< 32) - 1::little-32>>

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
    for {k, v} <- map, reduce: new(%{}, hash_prefix) do
      hashed_map -> put_in(hashed_map, [k], v)
    end
  end

  def get(map, key) do
    Map.get(map.hashed_map, hkey(map.hash_prefix, key))
  end

  def drop(map, keys) do
    {items_in_storage, octets_in_storage} =
      for key <- keys, reduce: {map.items_in_storage, map.octets_in_storage} do
        {items_in_storage, octets_in_storage} ->
          hkey = hkey(map.hash_prefix, key)

          case Map.get(map.hashed_map, hkey) do
            nil ->
              {items_in_storage, octets_in_storage}

            value ->
              # Formula (9.8) v0.6.7
              # ai ≡ 2⋅∣al∣ + ∣as∣
              # ao ∈ N2^64 ≡ sum(81 + z) + sum(34 + |x| + |y|),
              case key do
                {_, l} ->
                  {items_in_storage - 2, octets_in_storage - 81 - l}

                k ->
                  {items_in_storage - 1, octets_in_storage - 34 - byte_size(k) - byte_size(value)}
              end
          end
      end

    %__MODULE__{
      original_map: Map.drop(map.original_map, keys),
      hashed_map: Map.drop(map.hashed_map, Enum.map(keys, fn k -> hkey(map.hash_prefix, k) end)),
      items_in_storage: items_in_storage,
      octets_in_storage: octets_in_storage
    }
  end

  # Access callbacks
  def fetch(%__MODULE__{} = m, key) do
    case Map.fetch(m.hashed_map, hkey(m.hash_prefix, key)) do
      {:ok, v} -> {:ok, v}
      :error -> :error
    end
  end

  def get_and_update(%__MODULE__{} = m, key, fun) when is_function(fun) do
    hashed = hkey(m.hash_prefix, key)
    old = Map.get(m.hashed_map, hashed)

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
    hashed = hkey(m.hash_prefix, key)

    {new_count, new_size} =
      case key do
        {_, l} ->
          case old do
            nil -> {m.items_in_storage + 2, m.octets_in_storage + 81 + l}
            _ -> {m.items_in_storage, m.octets_in_storage}
          end

        _ ->
          case old do
            nil ->
              {m.items_in_storage + 1,
               m.octets_in_storage + 34 + byte_size(key) + byte_size(new_val)}

            old_val ->
              {
                m.items_in_storage,
                m.octets_in_storage + byte_size(new_val) - byte_size(old_val)
              }
          end
      end

    new_struct = %__MODULE__{
      original_map: Map.put(m.original_map, key, new_val),
      hashed_map: Map.put(m.hashed_map, hashed, new_val),
      items_in_storage: new_count,
      octets_in_storage: new_size
    }

    {get_val, new_struct}
  end

  def pop(%__MODULE__{} = m, key) do
    val = Map.get(m.hashed_map, hkey(m.hash_prefix, key))

    {val, drop(m, [key])}
  end

  def has_key?(map, key), do: Map.has_key?(map.hashed_map, hkey(map.hash_prefix, key))

  defp hkey(_, {h, l}), do: hkey({h, l})

  defp hkey(prefix, key) do
    <<hashed_key::binary-size(27), _::binary>> = h(prefix <> key)
    hashed_key
  end

  defp hkey({h, l}) do
    key = <<l::32-little>> <> h
    <<hashed_key::binary-size(27), _::binary>> = h(key)
    hashed_key
  end

  defp hkey(key) do
    <<hashed_key::binary-size(27), _::binary>> = h(key)
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
