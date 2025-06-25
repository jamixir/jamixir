defmodule Block.Extrinsic.Guarantee.WorkDigestTest do
  alias Block.Extrinsic.Guarantee.WorkDigest
  alias Util.Hash
  use ExUnit.Case
  import Codec.Encoder
  import Jamixir.Factory
  import Util.Hex, only: [b16: 1]

  setup do
    {:ok, wd: build(:work_digest)}
  end

  describe "encode/1" do
    test "encodes a work digest", %{wd: wd} do
      assert Encodable.encode(wd) ==
               "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\x03\0\0\0\0\0\0\0\0\x01\x04\t\x05\a\b\x06"
    end

    test "encode when output is an error", %{wd: wd} do
      wd = Map.put(wd, :result, {:error, :out_of_gas})

      assert Encodable.encode(wd) ==
               "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\x03\0\0\0\0\0\0\0\x01\t\x05\a\b\x06"
    end
  end

  describe "decode/1" do
    test "decodes a work digest", %{wd: wd} do
      {decoded, _} = WorkDigest.decode(e(wd))
      assert decoded == wd
    end

    test "decodes a work digest with big integer values", %{wd: wd} do
      big = 2 ** 64 - 1

      wd = %{
        wd
        | gas_used: big,
          imports: big,
          extrinsic_count: big,
          extrinsic_size: big,
          exports: big
      }

      {decoded, _} = WorkDigest.decode(e(wd))
      assert decoded == wd
    end

    test "decodes a work digest with error", %{wd: wd} do
      wd = put_in(wd.result, {:error, :panic})
      encoded = Encodable.encode(wd)
      {decoded, _} = WorkDigest.decode(encoded)
      assert decoded == wd
    end
  end

  describe "new/1 from work item" do
    test "creates a work result from a work item" do
      wi = build(:work_item)
      output = {:ok, Hash.zero()}
      wr = WorkDigest.new(wi, output)
      assert wr.service == wi.service
      assert wr.code_hash == wi.code_hash
      assert wr.payload_hash == Hash.default(wi.payload)
      assert wr.gas_ratio == wi.refine_gas_limit
      assert wr.result == output
    end
  end

  describe "to_json/1" do
    test "encodes a work digest to json", %{wd: wd} do
      json = Codec.JsonEncoder.encode(wd)

      assert json == %{
               code_hash: b16(wd.code_hash),
               payload_hash: b16(wd.payload_hash),
               service_id: wd.service,
               accumulate_gas: wd.gas_ratio,
               result: %{ok: b16(elem(wd.result, 1))},
               exports: 6,
               extrinsic_count: 7,
               extrinsic_size: 8,
               imports: 5,
               gas_used: 9
             }
    end

    test "encodes a work digest with error to json", %{wd: wd} do
      wd = put_in(wd.result, {:error, :panic})
      json = Codec.JsonEncoder.encode(wd)

      assert json == %{
               code_hash: b16(wd.code_hash),
               payload_hash: b16(wd.payload_hash),
               service_id: wd.service,
               accumulate_gas: wd.gas_ratio,
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
