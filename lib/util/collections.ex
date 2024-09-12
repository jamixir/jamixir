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

  @doc """
  Checks if the given list has no duplicates and is in order according to the provided key function and comparator.

  ## Parameters
  - list: The list to check for uniqueness and order
  - key_fn: Function to extract the key to compare. If not provided, the element itself is used as the key.
  - comparator: Function to compare two elements. Defaults to `&<=/2` for ascending order.

  ## Returns
  - {:ok, :valid} if the list has no duplicates and is in order
  - {:error, :duplicates} if duplicates are found
  - {:error, :not_in_order} if the list is not in order

  """

  @spec validate_unique_and_ordered(list(), (any() -> any()), (any(), any() -> boolean())) ::
          {:ok, :valid} | {:error, :duplicates | :not_in_order}
  def validate_unique_and_ordered(list, key_fn \\ & &1, comparator \\ &<=/2)

  def validate_unique_and_ordered([], _key_fn, _comparator), do: {:ok, :valid}
  def validate_unique_and_ordered([_], _key_fn, _comparator), do: {:ok, :valid}

  def validate_unique_and_ordered([a | rest], key_fn, comparator) do
    do_validate_unique_and_ordered(rest, key_fn.(a), MapSet.new([key_fn.(a)]), key_fn, comparator)
  end

  defp do_validate_unique_and_ordered([], _last_key, _seen, _key_fn, _comparator),
    do: {:ok, :valid}

  defp do_validate_unique_and_ordered([item | rest], last_key, seen, key_fn, comparator) do
    current_key = key_fn.(item)

    cond do
      MapSet.member?(seen, current_key) ->
        {:error, :duplicates}

      not comparator.(last_key, current_key) ->
        {:error, :not_in_order}

      true ->
        do_validate_unique_and_ordered(
          rest,
          current_key,
          MapSet.put(seen, current_key),
          key_fn,
          comparator
        )
    end
  end
end
