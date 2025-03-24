defmodule Block.Extrinsic.Guarantee.WorkResultTest do
  alias Block.Extrinsic.Guarantee.WorkResult
  alias Util.{Hash, Hex}
  use ExUnit.Case
  use Codec.Encoder
  import Jamixir.Factory

  setup do
    {:ok, wr: build(:work_result)}
  end

  describe "encode/1" do
    test "encodes a work result", %{wr: wr} do
      assert Encodable.encode(wr) ==
               "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\x03\0\0\0\0\0\0\0\0\x01\x04\t\x05\a\b\x06"
    end

    test "encode when output is an error", %{wr: wr} do
      wr = Map.put(wr, :result, {:error, :out_of_gas})

      assert Encodable.encode(wr) ==
               "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\x03\0\0\0\0\0\0\0\x01\t\x05\a\b\x06"
    end
  end

  describe "decode/1" do
    test "decodes a work result", %{wr: wr} do
      {decoded, _} = WorkResult.decode(e(wr))
      assert decoded == wr
    end

    test "decodes a work result with big integer values", %{wr: wr} do
      big = 2 ** 64 - 1

      wr = %{
        wr
        | gas_used: big,
          imports: big,
          extrinsic_count: big,
          extrinsic_size: big,
          exports: big
      }

      {decoded, _} = WorkResult.decode(e(wr))
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

  describe "to_json/1" do
    test "encodes a work result to json", %{wr: wr} do
      json = Codec.JsonEncoder.encode(wr)

      assert json == %{
               code_hash: Hex.encode16(wr.code_hash, prefix: true),
               payload_hash: Hex.encode16(wr.payload_hash, prefix: true),
               service_id: wr.service,
               accumulate_gas: wr.gas_ratio,
               result: %{ok: Hex.encode16(elem(wr.result, 1), prefix: true)},
               exports: 6,
               extrinsic_count: 7,
               extrinsic_size: 8,
               imports: 5,
               gas_used: 9
             }
    end

    test "encodes a work result with error to json", %{wr: wr} do
      wr = put_in(wr.result, {:error, :panic})
      json = Codec.JsonEncoder.encode(wr)

      assert json == %{
               code_hash: Hex.encode16(wr.code_hash, prefix: true),
               payload_hash: Hex.encode16(wr.payload_hash, prefix: true),
               service_id: wr.service,
               accumulate_gas: wr.gas_ratio,
               result: %{:panic => nil},
               imports: 5,
               exports: 6,
               extrinsic_count: 7,
               extrinsic_size: 8,
               gas_used: 9
             }
    end
  end
end
