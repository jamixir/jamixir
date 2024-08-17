defmodule BlockTest do
  use ExUnit.Case
  import Jamixir.Factory

  describe "encode/1" do
    test "encode block smoke test" do
      Codec.Encoder.encode(build(:block))
    end
  end
end
