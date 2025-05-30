defmodule Util.Math do
  @doc """
  Sums a specific field from a collection of maps/structs.

  """
  @spec sum_field(Enumerable.t(), atom()) :: number()
  def sum_field(collection, field) do
    for item <- collection, reduce: 0 do
      acc -> acc + Map.get(item, field, 0)
    end
  end

  @doc """
  Sums the results of applying a function to each element in a collection.
  """
  @spec sum_by(Enumerable.t(), (any() -> number())) :: number()
  def sum_by(collection, fun) when is_function(fun, 1) do
    for item <- collection, reduce: 0 do
      acc -> acc + fun.(item)
    end
  end
end
