defmodule Util.ShuffleTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Shuffle

  describe "Fisher-Yates shuffle" do
    test "shuffle integer list - numeric sequence same length - same order 1" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [0, 0, 0, 0, 0, 0]
      assert Shuffle.shuffle(list, positions) == [1, 2, 3, 4, 5, 6]
    end

    test "shuffle integer list - numeric sequence same length - same order 2" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [6, 5, 4, 3, 2, 1]
      assert Shuffle.shuffle(list, positions) == [1, 2, 3, 4, 5, 6]
    end

    test "shuffle integer list - numeric sequence same length - reverse order" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [5, 4, 3, 2, 1, 0]
      assert Shuffle.shuffle(list, positions) == [6, 5, 4, 3, 2, 1]
    end

    test "shuffle integer list - numeric sequence same length - zig-zag order" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [0, 4, 0, 2, 0, 0]
      assert Shuffle.shuffle(list, positions) == [1, 6, 2, 5, 3, 4]
    end

    test "shuffle integer list - numeric sequence same length - randomly picked permutation order" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [8, 3, 3, 1, 1, 0]
      assert Shuffle.shuffle(list, positions) == [3, 5, 6, 2, 4, 1]
    end

    test "shuffle integer list - numeric sequence greater length - same order 1" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
      assert Shuffle.shuffle(list, positions) == [1, 2, 3, 4, 5, 6]
    end

    test "shuffle integer list - numeric sequence greater length - same order 2" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [6, 5, 4, 3, 2, 1, 543, 7665, 2131_312, 7777]
      assert Shuffle.shuffle(list, positions) == [1, 2, 3, 4, 5, 6]
    end

    test "shuffle integer list - numeric sequence greater length - reverse order" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [5, 4, 3, 2, 1, 0, 7, 7, 7, 7, 3]
      assert Shuffle.shuffle(list, positions) == [6, 5, 4, 3, 2, 1]
    end

    test "shuffle integer list - numeric sequence greater length - zig-zag order" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [0, 4, 0, 2, 0, 0, 0, 0, 1, 1, 2, 0]
      assert Shuffle.shuffle(list, positions) == [1, 6, 2, 5, 3, 4]
    end

    test "shuffle integer list - numeric sequence greater length - randomly picked permutation order" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [8, 3, 3, 1, 1, 0, 0, 0, 1, 1, 2]
      assert Shuffle.shuffle(list, positions) == [3, 5, 6, 2, 4, 1]
    end

    test "shuffle integer list - numeric sequence - 33 elements in order" do
      list = Enum.to_list(1..33)

      positions = List.duplicate(0, 33)

      assert Shuffle.shuffle(list, positions) == Enum.to_list(1..33)
    end

    test "shuffle integer list - hash to numeric sequence" do
      list = [1, 2, 3, 4, 5, 6]
      hash = shuffle_hash_factory()
      assert Shuffle.shuffle(list, hash) == [4, 3, 6, 5, 1, 2]
    end

    test "shuffle integer list - hash to numeric sequence - over 32 elements" do
      list = Enum.to_list(1..33)

      hash = shuffle_hash_factory()

      assert Shuffle.shuffle(list, hash) == [
               10,
               15,
               25,
               30,
               13,
               26,
               32,
               3,
               16,
               1,
               11,
               12,
               5,
               24,
               28,
               20,
               8,
               17,
               27,
               4,
               2,
               22,
               21,
               23,
               6,
               19,
               29,
               33,
               14,
               18,
               9,
               7,
               31
             ]
    end
  end
end
