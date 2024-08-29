defmodule Util.ShuffleTest do
  use ExUnit.Case

  alias Shuffle

  describe "Fisher-Yates shuffle" do
    test "shuffle integer list 1 - numeric sequence" do
      list = [1, 2]
      positions = [1, 0]
      assert Shuffle.shuffle(list, positions) == [2, 1]
    end

    test "shuffle integer list 2 - numeric sequence" do
      list = [1, 2]
      positions = [1, 0, 5, 6]
      assert Shuffle.shuffle(list, positions) == [2, 1]
    end

    test "shuffle integer list 3 - numeric sequence" do
      list = [1, 2]
      positions = [2, 0, 5, 6]
      assert Shuffle.shuffle(list, positions) == [1, 2]
    end

    test "shuffle integer list 1 - hash" do
      list = [1, 2]
      hash = Util.Hash.blake2b_n(<<"hello">>, 32)
      assert Shuffle.shuffle(list, hash) == [2, 1]
    end
  end
end
