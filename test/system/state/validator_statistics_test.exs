defmodule System.State.ValidatorStatisticsTest do
  use ExUnit.Case
  import Jamixir.Factory

  describe "encode/1" do
    test "encode smoke test" do
      assert Codec.Encoder.encode(build(:validator_statistics)) ==
               <<1, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5, 6>>
    end
  end
end
