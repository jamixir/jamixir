defmodule WorkItemTest do
  alias Block.Extrinsic.Guarantee.WorkResult
  alias Util.Hash
  alias Block.Extrinsic.WorkItem
  use ExUnit.Case
  import Jamixir.Factory

  setup do
    {:ok, wi: build(:work_item)}
  end

  describe "encode/1" do
    test "encodes a work result", %{wi: wi} do
      assert Codec.Encoder.encode(wi) ==
               "\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\x01\x02\x03\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04\x05\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x06\a\0\0\0\b\0"
    end
  end

  describe "to_work_result/2" do
    test "transform work report in work result" do
      output = {:ok, "output"}

      work_report =
        build(:work_item,
          service: 1,
          code_hash: <<1, 2, 3>>,
          payload: <<4, 5>>,
          refine_gas_limit: 6,
          import_segments: [{<<1, 2, 3>>, 4}, {<<1, 2, 3>>, 4}],
          export_count: 9,
          extrinsic: [{<<1, 2, 3>>, 4}, {<<1, 2, 3>>, 4}]
        )

      result = WorkItem.to_work_result(work_report, output, 77)

      assert result == %WorkResult{
               service: 1,
               code_hash: <<1, 2, 3>>,
               payload_hash: Hash.default(<<4, 5>>),
               gas_ratio: 6,
               result: output,
               gas_used: 77,
               imports: 2,
               exports: 9,
               extrinsic_count: 2,
               extrinsic_size: 8
             }
    end
  end
end
