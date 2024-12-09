defmodule Block.Extrinsic.Guarantee.WorkResultTest do
  alias Block.Extrinsic.Guarantee.WorkResult
  alias Util.Hash
  use ExUnit.Case
  import Jamixir.Factory

  setup do
    {:ok, wr: build(:work_result)}
  end

  describe "encode/1" do
    test "encodes a work result", %{wr: wr} do
      assert Encodable.encode(wr) ==
               "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\x03\0\0\0\0\0\0\0\0\x01\x04"
    end

    test "encode when output is an error", %{wr: wr} do
      wr = Map.put(wr, :result, {:error, :out_of_gas})

      assert Encodable.encode(wr) ==
               "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\x03\0\0\0\0\0\0\0\x01"
    end
  end

  describe "decode/1" do
    test "decodes a work result", %{wr: wr} do
      encoded = Encodable.encode(wr)
      {decoded, _} = WorkResult.decode(encoded)
      assert decoded == wr
    end

    test "decodes a work result with error", %{wr: wr} do
      wr = put_in(wr.result, {:error, :panic})
      encoded = Encodable.encode(wr)
      {decoded, _} = WorkResult.decode(encoded)
      assert decoded == wr
    end
  end

  describe "new/1 from work item" do
    test "creates a work result from a work item" do
      wi = build(:work_item)
      output = {:ok, Hash.zero()}
      wr = WorkResult.new(wi, output)
      assert wr.service == wi.service
      assert wr.code_hash == wi.code_hash
      assert wr.payload_hash == Hash.default(wi.payload)
      assert wr.gas_ratio == wi.refine_gas_limit
      assert wr.result == output
    end
  end
end
