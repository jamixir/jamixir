defmodule WorkPackageTest do
  alias Block.Extrinsic.WorkPackageBundle
  alias Block.Extrinsic.WorkPackage
  alias System.State
  alias Util.Hash
  use ExUnit.Case
  import Jamixir.Factory
  import Constants
  import Codec.Encoder
  import Mox

  setup_all do
    {:ok, wp: build(:work_package, service: 0), state: build(:genesis_state)}
  end

  describe "valid?/1" do
    @big_binary max_work_package_size() * 8
    test "validates a work package", %{wp: wp} do
      assert WorkPackage.valid?(wp)
    end

    test "validates invalid gas", %{wp: wp} do
      assert WorkPackage.valid?(%{wp | work_items: [build(:work_item, refine_gas_limit: 1)]})

      refute WorkPackage.valid?(%{
               wp
               | work_items: [build(:work_item, refine_gas_limit: Constants.gas_refine())]
             })

      refute WorkPackage.valid?(%{
               wp
               | work_items: [
                   build(:work_item, accumulate_gas_limit: Constants.gas_accumulation())
                 ]
             })
    end

    test "validates too many extrinsics", %{wp: wp} do
      half_size_extrinsic = for _ <- 1..div(Constants.max_extrinsics(), 2), do: {Hash.zero(), 1}
      wi = build(:work_item, extrinsic: half_size_extrinsic)
      assert WorkPackage.valid?(%{wp | work_items: [wi]})
      assert WorkPackage.valid?(%{wp | work_items: [wi, wi]})
      refute WorkPackage.valid?(%{wp | work_items: [wi, wi, wi]})
    end

    test "invalid amount of work items", %{wp: wp} do
      [wi | _] = wp.work_items
      # empty wi not allowed
      refute WorkPackage.valid?(%{wp | work_items: []})

      refute WorkPackage.valid?(%{
               wp
               | work_items: for(_ <- 1..(Constants.max_work_items() + 1), do: wi)
             })
    end

    test "invalid when the sum of export_count exceeds the maximum", %{wp: wp} do
      big_work_item =
        build(:work_item, export_count: Constants.max_imports() + 1)

      refute WorkPackage.valid?(%{wp | work_items: [big_work_item]})
    end

    test "invalid when work item payload is big", %{wp: wp} do
      big_work_item =
        build(:work_item, payload: <<0::size(max_work_package_size() * 8)>>)

      refute WorkPackage.valid?(%{wp | work_items: [big_work_item]})
    end

    test "invalid when the sum of import_segments exceeds the maximum", %{wp: wp} do
      data_segments = for _ <- 1..2500, do: {Hash.zero(), 1}
      medium_work_item = build(:work_item, import_segments: data_segments)
      big_work_item = build(:work_item, import_segments: data_segments ++ data_segments)

      assert WorkPackage.valid?(%{wp | work_items: [medium_work_item]})
      refute WorkPackage.valid?(%{wp | work_items: [medium_work_item, medium_work_item]})
      refute WorkPackage.valid?(%{wp | work_items: [big_work_item]})
    end

    test "invalid when binaries also extrapolate maximum", %{wp: wp} do
      refute WorkPackage.valid?(%{wp | parameterization_blob: <<0::size(@big_binary)>>})

      refute WorkPackage.valid?(%{wp | authorization_token: <<0::size(@big_binary)>>})
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
      [ds1 | rest] = for _ <- 1..2862, do: {Hash.zero(), 4_104}
      [ex1 | ex_rest] = for _ <- 1..100, do: {Hash.zero(), 105_310}

      in_limit_work_item =
        build(:work_item, import_segments: rest, extrinsic: [ex_rest])

      big_work_item =
        build(:work_item,
          import_segments: [ds1 | rest],
          extrinsic: [ex1 | ex_rest]
        )

      # WS*WC = 4104
      # |ii| = 500 => 500 * 4104 = 2_052_000
      # Max: 13_794_305 - 2_052_000 = 11_742_305
      # 11_742_305 / 4104 = 2862
      assert WorkPackage.valid?(%{wp | work_items: [in_limit_work_item]})
      refute WorkPackage.valid?(%{wp | work_items: [big_work_item]})
    end
  end

  # Formula (14.10) v0.7.0
  describe "authorization_code/2" do
    test "returns authorization_code when it is available in history", %{state: state} do
      h = Hash.random()

      service_account =
        build(:service_account,
          preimage_storage_p: %{h => <<0, 7, 7, 7>>},
          storage: HashedKeysMap.new(%{{h, 4} => [1]}),
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

    test "returns authorization_code when it is available in history - 2", %{state: state} do
      h = Hash.random()
      p_m = Hash.random()

      service_account =
        build(:service_account,
          preimage_storage_p: %{h => <<32, p_m::binary-size(32), 7, 7, 7>>},
          storage: HashedKeysMap.new(%{{h, 36} => [1]}),
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
    test "encode and decode a work package", %{wp: wp} do
      assert WorkPackage.decode(Codec.Encoder.encode(wp)) == {wp, <<>>}
    end
  end

  describe "valid_gas?/1" do
    test "validates maximum accumulation gas" do
      item = build(:work_item, accumulate_gas_limit: Constants.gas_accumulation() - 1)
      assert WorkPackage.valid_gas?(build(:work_package, work_items: [item]))
      refute WorkPackage.valid_gas?(build(:work_package, work_items: [item, item]))
    end

    test "validates maximum refine gas" do
      item = build(:work_item, refine_gas_limit: Constants.gas_refine() - 1)
      assert WorkPackage.valid_gas?(build(:work_package, work_items: [item]))
      refute WorkPackage.valid_gas?(build(:work_package, work_items: [item, item]))
    end
  end

  describe "valid_data_segments?/1" do
    test "segment count is below limit" do
      wp = build(:work_package, work_items: [build(:work_item), build(:work_item)])
      assert WorkPackage.valid_data_segments?(wp)
    end

    test "export count sum is above limit" do
      wi = build(:work_item, export_count: Constants.max_imports() / 2)
      wp1 = build(:work_package, work_items: [wi])
      wp2 = build(:work_package, work_items: [wi, wi, wi])

      assert WorkPackage.valid_data_segments?(wp1)
      refute WorkPackage.valid_data_segments?(wp2)
    end

    test "segment size is abo limit" do
      segments = for _ <- 1..div(Constants.max_imports(), 2), do: {Hash.zero(), 256}
      wi = build(:work_item, import_segments: segments)
      wp1 = build(:work_package, work_items: [wi])
      wp2 = build(:work_package, work_items: [wi, wi, wi])
      assert WorkPackage.valid_data_segments?(wp1)
      refute WorkPackage.valid_data_segments?(wp2)
    end
  end

  describe "valid_extrinsics?/2" do
    test "valid empty extrinsics" do
      wp = build(:work_package, work_items: [])
      assert WorkPackage.valid_extrinsics?(wp, [])
    end

    test "valid items with no extrinsics" do
      wp = build(:work_package, work_items: [build(:work_item, extrinsic: [])])
      assert WorkPackage.valid_extrinsics?(wp, [])
    end

    test "valid extrinsics" do
      {work_package, extrinsics} = work_package_and_its_extrinsic_factory()
      assert WorkPackage.valid_extrinsics?(work_package, extrinsics)
    end

    test "invalid extrinsics" do
      {work_package, _} = work_package_and_its_extrinsic_factory()
      refute WorkPackage.valid_extrinsics?(work_package, [])
    end
  end

  describe "bundle encoding and decoding" do
    test "smoke test bundle" do
      work_package = build(:work_package)
      # extrinsic in work item factory
      Storage.put(<<1, 2, 3, 4, 5, 6, 7>>)

      # call DA 2 times, one segment on each of 2 work items
      expect(DAMock, :do_get_segment, 2, fn _, _ -> <<1::m(export_segment)>> end)
      expect(DAMock, :do_get_justification, 2, fn _, _ -> <<9::hash()>> end)
      bundle = WorkPackage.bundle(work_package)
      {dec, bin} = WorkPackageBundle.decode(e(bundle))

      assert dec == bundle
      assert bin == <<>>
      verify!()
    end
  end
end
