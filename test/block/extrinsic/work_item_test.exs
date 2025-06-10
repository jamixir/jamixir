defmodule WorkItemTest do
  alias Block.Extrinsic.Guarantee.WorkDigest
  alias Util.Hash
  alias Block.Extrinsic.WorkItem
  use ExUnit.Case
  import Jamixir.Factory
  import Codec.Encoder

  setup do
    {:ok, wi: build(:work_item)}
  end

  describe "encode/1" do
    test "encodes/decodes a work item", %{wi: wi} do
      assert WorkItem.decode(e(wi)) == {wi, <<>>}
    end

    test "encodes/decodes a work item with tagged hash variant", %{wi: wi} do
      tagged = Enum.map(wi.import_segments, fn {h, i} -> {{:tagged_hash, h}, i} end)
      wi = %{wi | import_segments: tagged}
      assert WorkItem.decode(e(wi)) == {wi, <<>>}
    end
  end

  describe "to_work_digest/2" do
    test "transform work report in work digest" do
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

      result = WorkItem.to_work_digest(work_report, output, 77)

      assert result == %WorkDigest{
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
