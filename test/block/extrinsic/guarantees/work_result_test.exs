defmodule Block.Extrinsic.Guarantee.WorkResultTest do
  use ExUnit.Case
  alias Block.Extrinsic.Guarantee.WorkResult

  setup do
    {:ok,
     wr: %WorkResult{
       service_index: 0,
       code_hash: <<1::256>>,
       payload_hash: <<2::256>>,
       gas_prioritization_ratio: 3,
       output_or_error: {:ok, <<4>>}
     }}
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
