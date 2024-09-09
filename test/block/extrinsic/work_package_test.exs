defmodule WorkPackageTest do
  alias Block.Extrinsic.WorkPackage
  use ExUnit.Case
  import Jamixir.Factory

  setup do
    {:ok, wp: build(:work_package)}
  end

  describe "valid?/1" do
    test "validates a work package", %{wp: wp} do
      assert WorkPackage.valid?(wp)
    end

    test "invalid when the sum of exported_data_segments_count exceeds the maximum", %{wp: wp} do
      refute WorkPackage.valid?(%{
               wp
               | work_items: [
                   build(:work_item,
                     exported_data_segments_count: WorkPackage.maximum_exported_items() + 1
                   )
                 ]
             })
    end

    test "invalid when the sum of imported_data_segments exceeds the maximum", %{wp: wp} do
      data_segments = Enum.map(1..1500, fn _ -> {<<0::256>>, 1} end)
      medium_work_item = build(:work_item, imported_data_segments: data_segments)
      big_work_item = build(:work_item, imported_data_segments: data_segments ++ data_segments)

      assert WorkPackage.valid?(%{wp | work_items: [medium_work_item]})
      refute WorkPackage.valid?(%{wp | work_items: [medium_work_item, medium_work_item]})
      refute WorkPackage.valid?(%{wp | work_items: [big_work_item]})
    end

    test "validates different work_item imported_data_segments content size", %{wp: wp} do
      medium_work_item =
        build(:work_item,
          imported_data_segments: [{<<0::256>>, 10_000_000}],
          blob_hashes_and_lengths: [{<<0::256>>, 10_000_000}]
        )

      big_work_item =
        build(:work_item,
          imported_data_segments: [{<<0::256>>, 20_000_000}],
          blob_hashes_and_lengths: [{<<0::256>>, 20_000_000}]
        )

      assert WorkPackage.valid?(%{wp | work_items: [medium_work_item]})
      refute WorkPackage.valid?(%{wp | work_items: [medium_work_item, medium_work_item]})
      refute WorkPackage.valid?(%{wp | work_items: [big_work_item]})
    end

    test "validates different work_item imported_data_segments length", %{wp: wp} do
      [ds1 | rest] = Enum.map(1..500, fn _ -> {<<0::256>>, 21_062} end)

      in_limit_work_item =
        build(:work_item, imported_data_segments: rest, blob_hashes_and_lengths: rest)

      big_work_item =
        build(:work_item,
          imported_data_segments: [ds1 | rest],
          blob_hashes_and_lengths: [ds1 | rest]
        )

      # WS*WC = 4104
      # |ii| = 500 => 500 * 4104 = 2_052_000
      # Max: 12_582_912 - 2_052_000 = 10_530_912
      # 10_530_912 / 500 = 21_061
      assert WorkPackage.valid?(%{wp | work_items: [in_limit_work_item]})
      refute WorkPackage.valid?(%{wp | work_items: [big_work_item]})
    end
  end

  describe "encode/1" do
    test "encodes a work package", %{wp: wp} do
      assert Codec.Encoder.encode(wp) ==
               "\x01\x01\x02\0\0\0\x03\x01\x04\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\x01\x02\x03\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04\x05\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x06\a\0\0\0\b\0"
    end
  end
end
