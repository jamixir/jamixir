defmodule Util.ShuffleTest do
  use ExUnit.Case
  use Codec.Encoder
  import Jamixir.Factory
  alias Shuffle
  alias Util.Hash

  describe "Fisher-Yates shuffle" do
    test "shuffle integer list - numeric sequence same length - same order 1" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [0, 0, 0, 0, 0, 0]
      assert Shuffle.shuffle(list, positions) == [1, 6, 5, 4, 3, 2]
    end

    test "shuffle integer list - numeric sequence same length - same order 2" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [6, 5, 4, 3, 2, 1]
      assert Shuffle.shuffle(list, positions) == [1, 6, 5, 4, 3, 2]
    end

    test "shuffle integer list - numeric sequence same length - reverse order" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [5, 4, 3, 2, 1, 0]
      assert Shuffle.shuffle(list, positions) == [6, 5, 4, 3, 2, 1]
    end

    test "shuffle integer list - numeric sequence same length - zig-zag order" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [0, 4, 0, 2, 0, 0]
      assert Shuffle.shuffle(list, positions) == [1, 5, 6, 3, 4, 2]
    end

    test "shuffle integer list - numeric sequence same length - randomly picked permutation order" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [8, 3, 3, 1, 1, 0]
      assert Shuffle.shuffle(list, positions) == [3, 4, 5, 2, 6, 1]
    end

    test "shuffle integer list - numeric sequence greater length - same order 1" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
      assert Shuffle.shuffle(list, positions) == [1, 6, 5, 4, 3, 2]
    end

    test "shuffle integer list - numeric sequence greater length - same order 2" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [6, 5, 4, 3, 2, 1, 543, 7665, 2_131_312, 7777]
      assert Shuffle.shuffle(list, positions) == [1, 6, 5, 4, 3, 2]
    end

    test "shuffle integer list - numeric sequence greater length - reverse order" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [5, 4, 3, 2, 1, 0, 7, 7, 7, 7, 3]
      assert Shuffle.shuffle(list, positions) == [6, 5, 4, 3, 2, 1]
    end

    test "shuffle integer list - numeric sequence greater length - zig-zag order" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [0, 4, 0, 2, 0, 0, 0, 0, 1, 1, 2, 0]
      assert Shuffle.shuffle(list, positions) == [1, 5, 6, 3, 4, 2]
    end

    test "shuffle integer list - numeric sequence greater length - randomly picked permutation order" do
      list = [1, 2, 3, 4, 5, 6]
      positions = [8, 3, 3, 1, 1, 0, 0, 0, 1, 1, 2]
      assert Shuffle.shuffle(list, positions) == [3, 4, 5, 2, 6, 1]
    end

    test "shuffle integer list - numeric sequence - 33 elements in order" do
      list = Enum.to_list(1..33)

      positions = List.duplicate(0, 33)

      assert Shuffle.shuffle(list, positions) ==
               [1, 33, 32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16] ++
                 [15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2]
    end

    test "shuffle integer list - hash to numeric sequence" do
      list = [1, 2, 3, 4, 5, 6]
      hash = shuffle_hash_factory()
      assert Shuffle.shuffle(list, hash) == [4, 3, 6, 5, 1, 2]
    end

    test "shuffle integer list - hash to numeric sequence - over 32 elements" do
      list = Enum.to_list(1..33)

      hash = shuffle_hash_factory()

      assert Shuffle.shuffle(list, hash) ==
               [10, 14, 23, 27, 12, 22, 26, 3, 29, 1, 8, 31, 30, 15, 16, 11, 5, 7, 25, 2, 24, 28] ++
                 [19, 18, 13, 17, 20, 6, 21, 33, 32, 9, 4]
    end

    # Some test vectors from
    # https://github.com/w3f/jamtestvectors/pull/17/files#diff-a872479a9fbb18c5f8454df4a22544369d3fbcae58ff3f9e1854a130f62fdb8a
    test "shuffle integer list - hash to numeric sequence - 0 elements" do
      assert Shuffle.shuffle([], Hash.zero()) == []
    end

    test "shuffle integer list - hash to numeric sequence - 8 elements" do
      list = Enum.to_list(0..7)

      hash =
        Base.decode16!("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF")

      assert Shuffle.shuffle(list, hash) == [1, 2, 6, 0, 7, 4, 3, 5]
    end

    test "shuffle integer list - hash to numeric sequence - 20 elements" do
      hash =
        Base.decode16!("D111A554E3E8A058EA18C05BC943FA3CAD8FB1339BF9307F2F3D9228AE5C934B")

      assert Shuffle.shuffle(Enum.to_list(0..19), hash) ==
               [12, 5, 6, 0, 3, 2, 7, 4, 13, 17] ++ [18, 14, 16, 8, 11, 10, 19, 9, 15, 1]
    end
  end
end
