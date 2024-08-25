defmodule Util.Collections do
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

      if MapSet.member?(seen, key) do
        # Duplicate found, halt the iteration
        {:halt, true}
      else
        # Continue with updated set
        {:cont, MapSet.put(seen, key)}
      end
    end)
    |> Kernel.==(true)
  end

  def uniq_sorted(collection) do
    collection
    |> Enum.sort()
    |> Enum.uniq()
  end

  def uniq_sorted(collection, key_func) when is_function(key_func, 1) do
    collection
    |> Enum.sort_by(key_func)
    |> Enum.uniq_by(key_func)
  end
end
