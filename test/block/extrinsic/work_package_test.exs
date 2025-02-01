defmodule WorkPackageTest do
  alias System.State
  alias Util.Hash
  alias Block.Extrinsic.WorkPackage
  use ExUnit.Case
  import Jamixir.Factory

  setup_all do
    {:ok, wp: build(:work_package, service: 0), state: build(:genesis_state)}
  end

  describe "valid?/1" do
    test "validates a work package", %{wp: wp} do
      assert WorkPackage.valid?(wp)
    end

    test "invalid when the sum of export_count exceeds the maximum", %{wp: wp} do
      refute WorkPackage.valid?(%{
               wp
               | work_items: [
                   build(:work_item,
                     export_count: WorkPackage.maximum_exported_items() + 1
                   )
                 ]
             })
    end

    test "invalid when the sum of import_segments exceeds the maximum", %{wp: wp} do
      data_segments = for _ <- 1..1500, do: {Hash.zero(), 1}
      medium_work_item = build(:work_item, import_segments: data_segments)
      big_work_item = build(:work_item, import_segments: data_segments ++ data_segments)

      assert WorkPackage.valid?(%{wp | work_items: [medium_work_item]})
      refute WorkPackage.valid?(%{wp | work_items: [medium_work_item, medium_work_item]})
      refute WorkPackage.valid?(%{wp | work_items: [big_work_item]})
    end

    test "validates different work_item import_segments content size", %{wp: wp} do
      medium_work_item =
        build(:work_item,
          import_segments: [{Hash.zero(), 10_000_000}],
          extrinsic: [{Hash.zero(), 10_000_000}]
        )

      big_work_item =
        build(:work_item,
          import_segments: [{Hash.zero(), 20_000_000}],
          extrinsic: [{Hash.zero(), 20_000_000}]
        )

      assert WorkPackage.valid?(%{wp | work_items: [medium_work_item]})
      refute WorkPackage.valid?(%{wp | work_items: [medium_work_item, medium_work_item]})
      refute WorkPackage.valid?(%{wp | work_items: [big_work_item]})
    end

    test "validates different work_item import_segments length", %{wp: wp} do
      [ds1 | rest] = for _ <- 1..500, do: {Hash.zero(), 21_062}

      in_limit_work_item =
        build(:work_item, import_segments: rest, extrinsic: rest)

      big_work_item =
        build(:work_item,
          import_segments: [ds1 | rest],
          extrinsic: [ds1 | rest]
        )

      # WS*WC = 4104
      # |ii| = 500 => 500 * 4104 = 2_052_000
      # Max: 12_582_912 - 2_052_000 = 10_530_912
      # 10_530_912 / 500 = 21_061
      assert WorkPackage.valid?(%{wp | work_items: [in_limit_work_item]})
      refute WorkPackage.valid?(%{wp | work_items: [big_work_item]})
    end
  end

  # Formula (14.9) v0.6.0
  describe "authorization_code/2" do
    test "returns authorization_code when it is available in history", %{state: state} do
      h = Hash.random()

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

      state = %State{state | services: %{wp.service => service_account}}

      assert WorkPackage.authorization_code(wp, state.services) == <<7, 7, 7>>

      assert WorkPackage.implied_authorizer(wp, state.services) ==
               Hash.default(<<7, 7, 7>> <> wp.parameterization_blob)
    end

    test "return nil authorization code when it is not available", %{state: state} do
      assert WorkPackage.authorization_code(build(:work_package), state.services) == nil
    end
  end

  describe "encode/1" do
    test "encodes a work package", %{wp: wp} do
      assert Codec.Encoder.encode(wp) ==
               "\x01\x01\0\0\0\0\x03\x01\x04\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\x01\x02\x03\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04\x05\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x06\a\0\0\0\b\0"
    end
  end
end
