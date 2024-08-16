defmodule Block.Extrinsic.Guarantee.WorkResultTest do
  use ExUnit.Case
  import Jamixir.Factory

  setup do
    {:ok, wr: build(:work_result)}
  end

  describe "encode/1" do
    test "encodes a work result", %{wr: wr} do
      assert Codec.Encoder.encode(wr) ==
               "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\x03\0\0\0\0\0\0\0\0\x01\x04"
    end

    test "encode when output is an error", %{wr: wr} do
      wr = Map.put(wr, :output_or_error, {:error, :infinite})

      assert Codec.Encoder.encode(wr) ==
               "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\x03\0\0\0\0\0\0\0\x01"
    end
  end
end
