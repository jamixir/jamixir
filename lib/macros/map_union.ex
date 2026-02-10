defmodule MapUnion do
  @moduledoc """
  Provides extended `++` and `\\` operators that work with Maps and MapSets in addition to Lists.

  This module overrides the default `++` operator and introduces a `\\` operator for difference operations.

  ## Usage

      use MapUnion

  ## Examples

      %{a: 1} ++ %{b: 2}
      %{a: 1, b: 2}

      MapSet.new([1, 2]) ++ MapSet.new([2, 3])
      #MapSet<[1, 2, 3]>

      [1, 2] ++ [3, 4]
      [1, 2, 3, 4]

      %{a: 1, b: 2} \\ %{b: 2}
      %{a: 1}

  """

  defmacro __using__(_opts) do
    quote do
      import Kernel, except: [++: 2]
      import unquote(__MODULE__), only: [++: 2, \\: 2]
    end
  end

  @doc """
  Performs a union operation on two collections.

  This operator works with Maps, MapSets, and Lists:
  - For Maps, it performs a merge operation.
  - For MapSets, it performs a union operation.
  - For Lists, it concatenates them (same as the built-in `++`).

  ## Examples

      %{a: 1} ++ %{b: 2}
      %{a: 1, b: 2}

      MapSet.new([1, 2]) ++ MapSet.new([2, 3])
      #MapSet<[1, 2, 3]>

      [1, 2] ++ [3, 4]
      [1, 2, 3, 4]

  """
  @spec left ++ right :: map() | MapSet.t() | list()
        when left: map() | MapSet.t() | list(),
             right: map() | MapSet.t() | list()
  defmacro left ++ right do
    quote do
      MapUnion.union(unquote(left), unquote(right))
    end
  end

  @doc false
  def union(%MapSet{} = left, %MapSet{} = right), do: MapSet.union(left, right)
  def union(%{} = left, %{} = right), do: Map.merge(left, right)

  def union(left, right) when is_list(left) and is_list(right),
    do: Kernel.++(left, right)

  def union(_, _), do: raise(ArgumentError, "Unsupported types for ++ operator")

  @doc """
  Performs a difference operation on two collections.

  This operator works with Maps and MapSets:
  - For Maps, it removes keys from the left map that are present in the right map.
  - For MapSets, it performs a difference operation.

  ## Examples

      %{a: 1, b: 2, c: 3} \\ %{b: 2, d: 4}
      %{a: 1, c: 3}

      MapSet.new([1, 2, 3]) \\ MapSet.new([2, 3, 4])
      #MapSet<[1]>

  """
  @spec (left \\ right) :: map() | MapSet.t()
        when left: map() | MapSet.t(),
             right: map() | MapSet.t()
  # credo:disable-for-next-line
  defmacro left \\ right do
    quote do
      MapUnion.difference(unquote(left), unquote(right))
    end
  end

  @doc false
  def difference(%MapSet{} = left, %MapSet{} = right), do: MapSet.difference(left, right)
  def difference(%{} = left, %{} = right), do: Map.drop(left, Map.keys(right))
  def difference(_, _), do: raise(ArgumentError, "Unsupported types for \\ operator")
end
