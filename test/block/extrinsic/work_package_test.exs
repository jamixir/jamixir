defmodule WorkPackageTest do
  alias System.State
  alias Util.Hash
  alias Block.Extrinsic.WorkPackage
  use ExUnit.Case
  import Jamixir.Factory

  setup_all do
    {:ok, wp: build(:work_package, service_index: 0), state: build(:genesis_state)}
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

  # Formula (194) v0.4.1
  describe "authorization_code/2" do
    test "returns authorization_code when it is available in history", %{state: state} do
      h = :crypto.strong_rand_bytes(32)

      service_account =
        build(:service_account,
          preimage_storage_p: %{h => <<7, 7, 7>>},
          preimage_storage_l: %{{h, 3} => [1]},
          code_hash: h
        )

      wp =
        build(:work_package,
          authorization_code_hash: service_account.code_hash,
          context: build(:refinement_context, timeslot: 3)
        )

      state = %State{state | services: %{wp.service_index => service_account}}

      assert WorkPackage.authorization_code(wp, state) == <<7, 7, 7>>

      assert WorkPackage.implied_authorizer(wp, state) ==
               Hash.default(<<7, 7, 7>> <> wp.parameterization_blob)
    end

    test "return nil authorization code when it is not available", %{state: state} do
      assert WorkPackage.authorization_code(build(:work_package), state) == nil
    end
  end

  describe "encode/1" do
    test "encodes a work package", %{wp: wp} do
      assert Codec.Encoder.encode(wp) ==
               "\x01\x01\0\0\0\0\x03\x01\x04\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\x01\x02\x03\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04\x05\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x06\a\0\0\0\b\0"
    end
  end
end
