defmodule Util.CollectionsTest do
  use ExUnit.Case
  alias Util.Collections

  describe "has_duplicates" do
    @tag :list
    test "has_duplicates?/1 with a list without duplicates" do
      assert Collections.has_duplicates?([1, 2, 3, 4, 5]) == false
    end

    @tag :list
    test "has_duplicates?/1 with a list with duplicates" do
      assert Collections.has_duplicates?([1, 2, 3, 4, 1]) == true
    end

    @tag :map
    test "has_duplicates?/1 with a map without duplicates (checks keys)" do
      assert Collections.has_duplicates?(%{a: 1, b: 2, c: 3}) == false
    end

    @tag :map
    test "has_duplicates?/2 with a map checking for duplicate values" do
      assert Collections.has_duplicates?(%{a: 1, b: 2, c: 1}, fn {_, v} -> v end) == true
    end

    @tag :range
    test "has_duplicates?/1 with a range without duplicates" do
      assert Collections.has_duplicates?(1..10) == false
    end

    @tag :range
    test "has_duplicates?/1 with a range that would have duplicates if converted to list" do
      assert Collections.has_duplicates?(1..10 |> Enum.concat([10, 11])) == true
    end

    @tag :custom_comparator
    test "has_duplicates?/2 with a custom comparator on list of tuples" do
      assert Collections.has_duplicates?([{1, "a"}, {2, "b"}, {3, "a"}], fn {_, v} -> v end) ==
               true
    end

    @tag :custom_comparator
    test "has_duplicates?/2 with a custom comparator on list of tuples without duplicates" do
      assert Collections.has_duplicates?([{1, "a"}, {2, "b"}, {3, "c"}], fn {_, v} -> v end) ==
               false
    end
  end

  describe "validate_unique_and_ordered/3" do
    test "empty list is considered valid" do
      result = Util.Collections.validate_unique_and_ordered([])
      assert result == {:ok, :valid}
    end

    test "list with a single element is considered valid" do
      result = Util.Collections.validate_unique_and_ordered([1])
      assert result == {:ok, :valid}
    end

    test "list with unique and ordered elements is considered valid" do
      result = Util.Collections.validate_unique_and_ordered([1, 2, 3, 4, 5])
      assert result == {:ok, :valid}
    end

    test "list with duplicates returns an error" do
      result = Util.Collections.validate_unique_and_ordered([1, 2, 2, 3, 4])
      assert result == {:error, :duplicates}
    end

    test "list with out of order elements returns an error" do
      result = Util.Collections.validate_unique_and_ordered([1, 3, 2, 4, 5])
      assert result == {:error, :not_in_order}
    end

    test "custom key function is applied correctly" do
      result =
        Util.Collections.validate_unique_and_ordered(
          [%{id: 1}, %{id: 2}, %{id: 3}],
          & &1.id
        )

      assert result == {:ok, :valid}
    end

    test "custom comparator is applied correctly" do
      result =
        Util.Collections.validate_unique_and_ordered(
          [5, 4, 3, 2, 1],
          &(&1),
          &>=/2
        )

      assert result == {:ok, :valid}
    end

    test "list with duplicates based on custom key function returns an error" do
      result =
        Util.Collections.validate_unique_and_ordered(
          [%{id: 1}, %{id: 2}, %{id: 2}],
          & &1.id
        )

      assert result == {:error, :duplicates}
    end

    test "list with out of order elements based on custom comparator returns an error" do
      result =
        Util.Collections.validate_unique_and_ordered(
          [1, 2, 3, 4, 5],
          &(&1),
          &>=/2
        )

      assert result == {:error, :not_in_order}
    end
  end
end
