defmodule Util.Collections do
  use SelectiveMock

  use MapUnion

  @doc """
  Checks if there are any duplicates in the given collection.
  Works with any enumerable collection.
  """
  def has_duplicates?(collection) do
    has_duplicates?(collection, & &1)
  end

  @doc """
  Checks if there are any duplicates in the given collection based on the provided key function.
  Works with any enumerable collection.
  """
  def has_duplicates?(collection, key_func) when is_function(key_func, 1) do
    collection
    |> Enum.reduce_while(%MapSet{}, fn item, seen ->
      key = key_func.(item)

      if key in seen do
        # Duplicate found, halt the iteration
        {:halt, true}
      else
        # Continue with updated set
        {:cont, MapSet.put(seen, key)}
      end
    end)
    |> Kernel.==(true)
  end

  @doc """
  Checks if the given list has no duplicates and is in order according to the provided key function and comparator.

  ## Parameters
  - list: The list to check for uniqueness and order
  - key_fn: Function to extract the key to compare. If not provided, the element itself is used as the key.
  - comparator: Function to compare two elements. Defaults to `&<=/2` for ascending order.

  ## Returns
  - :ok if the list has no duplicates and is in order
  - {:error, :duplicates} if duplicates are found
  - {:error, :not_in_order} if the list is not in order

  """

  @spec validate_unique_and_ordered(list(), (any() -> any()), (any(), any() -> boolean())) ::
          :ok | {:error, :duplicates | :not_in_order}

  mockable validate_unique_and_ordered(list, key_fn \\ & &1, comparator \\ &<=/2) do
    list
    |> Enum.reduce_while({:ok, nil, MapSet.new()}, fn item, {_, last, seen} ->
      current = key_fn.(item)

      cond do
        last != nil and not comparator.(last, current) -> {:halt, {:error, :not_in_order}}
        current in seen -> {:halt, {:error, :duplicates}}
        true -> {:cont, {:ok, current, MapSet.put(seen, current)}}
      end
    end)
    |> case do
      {:ok, _, _} -> :ok
      error -> error
    end
  end

  def mock(:validate_unique_and_ordered, _), do: :ok

  # Formula (3.11) v0.6.5
  @spec union([map()]) :: map()
  def union([]), do: %{}

  def union([d1 | rest]) do
    d1 ++ union(rest)
  end

  @spec union_bin([binary()]) :: binary()
  def union_bin([]), do: <<>>

  def union_bin([d1 | rest]) do
    d1 <> union_bin(rest)
  end

  def all_ok?(collection, fun) do
    Enum.all?(collection, fn item ->
      fun.(item) == :ok
    end)
  end

  def key_for_value(map, value) do
    map
    |> Enum.find(fn {_key, val} -> val == value end)
    |> case do
      {key, _val} -> key
      nil -> nil
    end
  end
end
