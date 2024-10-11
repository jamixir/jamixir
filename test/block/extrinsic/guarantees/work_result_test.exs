defmodule Block.Extrinsic.Guarantee.WorkResultTest do
  alias Util.Hash
  alias Block.Extrinsic.Guarantee.WorkResult
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
      wr = Map.put(wr, :result, {:error, :infinite})

      assert Codec.Encoder.encode(wr) ==
               "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\x03\0\0\0\0\0\0\0\x01"
    end
  end

  describe "new/1 from work item" do
    test "creates a work result from a work item" do
      wi = build(:work_item)
      output = {:ok, <<0::256>>}
      wr = WorkResult.new(wi, output)
      assert wr.service_index == wi.service_id
      assert wr.code_hash == wi.code_hash
      assert wr.payload_hash == Hash.default(wi.payload_blob)
      assert wr.gas_prioritization_ratio == wi.gas_limit
      assert wr.result == output
    end
  end
end
