defmodule WorkReportTest do
  use ExUnit.Case
  import Codec.Encoder
  import Jamixir.Factory
  alias Util.MerkleTree
  alias Block.Extrinsic.AvailabilitySpecification
  alias Block.Extrinsic.Guarantee.{WorkDigest, WorkReport}
  alias Block.Extrinsic.WorkPackage
  alias Codec.JsonEncoder
  alias System.State.Ready
  alias System.State.ServiceAccount
  alias Util.Hash
  import Mox
  import Util.Hex, only: [b16: 1]

  setup_all do
    preimage = Hash.random()
    sa = ServiceAccount.store_preimage(build(:service_account), preimage, 0)

    Application.put_env(:jamixir, :erasure_coding, ErasureCodingMock)

    on_exit(fn ->
      Application.delete_env(:jamixir, :erasure_coding)
    end)

    {:ok,
     wp:
       build(:work_package,
         service: 0,
         parameterization_blob: <<1, 2, 3>>,
         authorization_code_hash: Hash.default(preimage)
       ),
     state: build(:genesis_state, services: %{0 => sa}),
     wr: build(:work_report)}
  end

  describe "encode/1" do
    test "encode/1 smoke test", %{wr: wr} do
      assert is_binary(e(wr))
    end
  end

  describe "decode/1" do
    test "decode/1 smoke test", %{wr: wr} do
      encoded = Codec.Encoder.encode(wr)
      {decoded, _} = WorkReport.decode(encoded)
      assert decoded == wr
    end

    test "decode/1 work report with segment root lookup", %{wr: wr} do
      put_in(wr.segment_root_lookup, %{Hash.one() => Hash.two()})
      encoded = Codec.Encoder.encode(wr)
      {decoded, _} = WorkReport.decode(encoded)
      assert decoded == wr
    end
  end

  describe "valid_size?/1" do
    test "returns true for a valid work report", %{wr: wr} do
      assert WorkReport.valid_size?(wr)
    end

    test "returns false when segment_root_lookup has more than 8 entries" do
      invalid_wr =
        build(:work_report,
          segment_root_lookup: for(i <- 1..9, into: %{}, do: {<<i::hash()>>, <<i::hash()>>})
        )

      refute WorkReport.valid_size?(invalid_wr)
    end

    test "returns false report is too big" do
      large_output = String.duplicate("a", Constants.max_work_report_size() + 1)
      invalid_wr = build(:work_report, output: large_output)
      refute WorkReport.valid_size?(invalid_wr)
    end

    test "returns false when report output + results is too big" do
      limit_output = String.duplicate("a", Constants.max_work_report_size())

      invalid_wr =
        build(:work_report,
          output: limit_output,
          digests: build_list(2, :work_digest, result: {:ok, <<1>>})
        )

      refute WorkReport.valid_size?(invalid_wr)
    end

    test "returns false when results results are too big" do
      limit_output = String.duplicate("a", Constants.max_work_report_size())

      invalid_wr =
        build(:work_report,
          output: <<>>,
          digests: build_list(2, :work_digest, result: {:ok, limit_output})
        )

      refute WorkReport.valid_size?(invalid_wr)
    end
  end

  describe "available_work_reports/2" do
    setup do
      # Create mock assurances using factory
      # 6 validators / 2 cores
      assurances = [
        build(:assurance, bitfield: <<0::6, 10::2>>),
        build(:assurance, bitfield: <<0::6, 10::2>>),
        build(:assurance, bitfield: <<0::6, 10::2>>),
        build(:assurance, bitfield: <<0::6, 11::2>>),
        build(:assurance, bitfield: <<0::6, 11::2>>),
        build(:assurance, bitfield: <<00::6, 00::2>>)
      ]

      # Create mock core reports using factory
      core_reports = [
        build(:core_report, work_report: build(:work_report, core_index: 0)),
        build(:core_report, work_report: build(:work_report, core_index: 1))
      ]

      %{assurances: assurances, core_reports: core_reports}
    end

    test "returns work reports for cores with sufficient assurances", %{
      assurances: assurances,
      core_reports: core_reports
    } do
      result = WorkReport.available_work_reports(assurances, core_reports)

      assert length(result) == 1
      assert for(x <- result, do: x.core_index) == [1]
    end

    test "returns empty list when no cores have sufficient assurances" do
      assurances = for _ <- 1..6, do: build(:assurance, bitfield: <<0>>)
      result = WorkReport.available_work_reports(assurances, [])
      assert result == []
    end

    test "handles case when all cores have sufficient assurances", %{core_reports: core_reports} do
      assurances = for _ <- 1..6, do: build(:assurance, bitfield: <<0::6, 11::2>>)
      result = WorkReport.available_work_reports(assurances, core_reports)
      assert length(result) == 2
      assert for(x <- result, do: x.core_index) == [0, 1]
    end

    test "handles empty assurances list" do
      result = WorkReport.available_work_reports([], [])

      assert result == []
    end
  end

  describe "separate_work_reports/2" do
    test "separates work reports based on prerequisites and dependencies" do
      w1 =
        build(:work_report,
          refinement_context: %{prerequisite: MapSet.new()},
          segment_root_lookup: %{}
        )

      w2 =
        build(:work_report,
          refinement_context: %{prerequisite: MapSet.new([Hash.one()])},
          segment_root_lookup: %{}
        )

      w3 =
        build(:work_report,
          refinement_context: %{prerequisite: MapSet.new()},
          segment_root_lookup: %{}
        )

      w4 =
        build(:work_report,
          refinement_context: %{prerequisite: MapSet.new([Hash.two()])},
          segment_root_lookup: %{}
        )

      w5 =
        build(:work_report,
          refinement_context: %{prerequisite: MapSet.new([Hash.three()])},
          segment_root_lookup: %{}
        )

      accumulated = %{}

      {w_bang, w_q} = WorkReport.separate_work_reports([w1, w2, w3, w4, w5], accumulated)

      assert w_bang == [w1, w3]
      assert [^w2, ^w4, ^w5] = Enum.map(w_q, fn {wr, _deps} -> wr end)
    end

    test "handles empty list" do
      assert {[], []} = WorkReport.separate_work_reports([], %{})
    end

    test "handles list with only prerequisites" do
      w1 =
        build(:work_report,
          refinement_context: %{prerequisite: MapSet.new([Hash.one()])},
          segment_root_lookup: %{}
        )

      w2 =
        build(:work_report,
          refinement_context: %{prerequisite: MapSet.new([Hash.two()])},
          segment_root_lookup: %{}
        )

      {w_bang, w_q} = WorkReport.separate_work_reports([w1, w2], %{})

      assert w_bang == []
      assert [^w1, ^w2] = Enum.map(w_q, fn {wr, _deps} -> wr end)
    end

    test "handles list with only non-prerequisites" do
      w1 =
        build(:work_report,
          refinement_context: %{prerequisite: MapSet.new()},
          segment_root_lookup: %{}
        )

      w2 =
        build(:work_report,
          refinement_context: %{prerequisite: MapSet.new()},
          segment_root_lookup: %{}
        )

      {w_bang, w_q} = WorkReport.separate_work_reports([w1, w2], %{})

      assert w_bang == [w1, w2]
      assert w_q == []
    end

    test "handles work reports with non-empty segment_root_lookup" do
      w1 =
        build(:work_report,
          refinement_context: %{prerequisite: MapSet.new()},
          segment_root_lookup: %{Hash.one() => Hash.two()}
        )

      w2 =
        build(:work_report,
          refinement_context: %{prerequisite: MapSet.new()},
          segment_root_lookup: %{}
        )

      {w_bang, w_q} = WorkReport.separate_work_reports([w1, w2], %{})

      assert w_bang == [w2]
      assert length(w_q) == 1
      assert [{^w1, deps}] = w_q
      assert MapSet.equal?(deps, MapSet.new([Hash.one()]))
    end
  end

  describe "with_dependencies/1" do
    test "returns work report with its dependencies" do
      w =
        build(:work_report,
          refinement_context: %{prerequisite: MapSet.new([Hash.one()])},
          segment_root_lookup: %{Hash.two() => Hash.three()}
        )

      assert {^w, deps} = WorkReport.with_dependencies(w)
      assert deps == MapSet.new([Hash.one(), Hash.two()])
    end
  end

  describe "edit_queue/2" do
    test "filters and updates the queue based on accumulated work" do
      w1 =
        build(:work_report,
          specification: %{work_package_hash: Hash.one()},
          segment_root_lookup: %{}
        )

      w2 =
        build(:work_report,
          specification: %{work_package_hash: Hash.two()},
          segment_root_lookup: %{Hash.three() => Hash.four()}
        )

      r = [{w1, MapSet.new()}, {w2, MapSet.new([Hash.three()])}]
      x = MapSet.new([Hash.two()])

      result = WorkReport.filter_and_update_dependencies(r, x)
      assert [{^w1, empty_set}] = result
      assert MapSet.equal?(empty_set, MapSet.new())
    end

    test "handles empty queue" do
      assert [] == WorkReport.filter_and_update_dependencies([], %{Hash.one() => Hash.two()})
    end

    test "filters out work reports with work package hash already in accumulated work" do
      w1 =
        build(:work_report,
          specification: %{work_package_hash: Hash.one()},
          segment_root_lookup: %{}
        )

      w2 =
        build(:work_report,
          specification: %{work_package_hash: Hash.two()},
          segment_root_lookup: %{}
        )

      r = [
        {w1, MapSet.new()},
        {w2, MapSet.new()}
      ]

      # w1's work package hash is already in x
      x = MapSet.new([Hash.one()])

      result = WorkReport.filter_and_update_dependencies(r, x)

      assert [{^w2, _}] = result
    end
  end

  describe "accumulation_priority_queue/2" do
    test "returns work reports in accumulation priority order" do
      w1 =
        build(:work_report,
          specification: %{work_package_hash: Hash.one(), exports_root: Hash.five()},
          segment_root_lookup: %{}
        )

      w2 =
        build(:work_report,
          specification: %{work_package_hash: Hash.two(), exports_root: Hash.one()},
          segment_root_lookup: %{Hash.three() => Hash.four()}
        )

      r = [{w1, MapSet.new()}, {w2, MapSet.new([Hash.three()])}]

      assert [^w1] = WorkReport.accumulation_priority_queue(r)
      assert [] = WorkReport.accumulation_priority_queue([])
    end
  end

  describe "accumulatable_work_reports/4" do
    setup do
      work_reports =
        for i <- 1..4 do
          build(:work_report,
            core_index: i,
            specification: %{work_package_hash: <<i::hash()>>, exports_root: <<i::hash()>>},
            refinement_context: %{prerequisite: MapSet.new()},
            segment_root_lookup: %{}
          )
        end

      [w1, w2, w3, w4] = work_reports

      # Modify w2 to have a prerequisite or non-empty segment_root_lookup
      w2 = %{
        w2
        | refinement_context: %{prerequisite: MapSet.new([Hash.one()])},
          segment_root_lookup: %{Hash.two() => Hash.three()}
      }

      %{
        w1: w1,
        w2: w2,
        w3: w3,
        w4: w4
      }
    end

    test "returns accumulatable work reports", %{w1: w1, w2: w2, w3: w3, w4: w4} do
      block_timeslot = 1
      accumulation_history = [%{}]

      ready_to_accumulate = [
        [
          %Ready{work_report: w3, dependencies: MapSet.new()}
        ],
        [%Ready{work_report: w4, dependencies: MapSet.new()}]
      ]

      result =
        WorkReport.accumulatable_work_reports(
          [w1, w2],
          block_timeslot,
          accumulation_history,
          ready_to_accumulate
        )

      # q =E(after_m ++ before_m ++ w_q) = E([w4,w3,w2]) = [w4,w3, w2]
      # W* = w! ++ Q(q) = [w1] ++ [w4,w3] = [w1,w4,w3]
      assert [^w1, ^w4, ^w3] = result
    end
  end

  @size Constants.segment_size() * 8
  describe "paged_proofs/2" do
    test "paged proof smoke test" do
      bytes = for _ <- 1..10, do: <<7::@size>>
      proofs = WorkReport.paged_proofs(bytes)
      assert length(proofs) == 2
      assert Enum.all?(proofs, &(byte_size(&1) == Constants.segment_size()))
    end

    test "paged proof empty bytestring" do
      proofs = WorkReport.paged_proofs([])
      assert length(proofs) == 1
      assert Enum.all?(proofs, &(byte_size(&1) == Constants.segment_size()))
    end
  end

  describe "process_item/3" do
    setup do
      Application.put_env(:jamixir, :pvm, MockPVM)
      stub(MockPVM, :do_refine, fn _, _, _, _, _, _, _ -> {<<1>>, [<<1>>], 555} end)

      on_exit(fn ->
        Application.put_env(:jamixir, :pvm, PVM)
      end)

      :ok
    end

    # case |e| != we
    test "bad exports", %{wp: wp, state: state} do
      stub(MockPVM, :do_refine, fn _, _, _, _, _, _, _ -> {<<1>>, [<<1>>], 555} end)

      wi = build(:work_item, export_count: 4)
      wp = %WorkPackage{wp | work_items: [wi]}
      {r, _u, _e} = WorkReport.process_item(wp, 0, <<>>, [], state.services, %{})
      assert r == :bad_exports
    end

    # case r not binary
    test "processes a work item error in PVM", %{wp: wp, state: state} do
      stub(MockPVM, :do_refine, fn _, _, _, _, _, _, _ -> {:bad, [<<1>>], 555} end)

      wi = build(:work_item, export_count: 1)
      wp = %WorkPackage{wp | work_items: [wi]}
      {r, _u, e} = WorkReport.process_item(wp, 0, <<>>, [], state.services, %{})
      assert r == :bad
      assert length(e) == 1
    end

    # case r binary too small
    test "oversize", %{wp: wp, state: state} do
      stub(MockPVM, :do_refine, fn _, _, _, _, _, _, _ -> {<<>>, [<<1>>], 555} end)
      o = String.duplicate(<<1>>, Constants.max_work_report_size() + 1)
      wi = build(:work_item, export_count: 1)
      wp = %WorkPackage{wp | work_items: [wi]}
      {r, _u, e} = WorkReport.process_item(wp, 0, o, [], state.services, %{})
      assert r == :oversize
      assert length(e) == 1
    end

    # case r binary and o(auhtorizer output) is correct size
    test "all good", %{wp: wp, state: state} do
      stub(MockPVM, :do_refine, fn _, _, _, _, _, _, _ -> {<<2>>, [<<1>>], 555} end)
      wi = build(:work_item, export_count: 1)
      wp = %WorkPackage{wp | work_items: [wi]}

      {r, _u, e} = WorkReport.process_item(wp, 0, <<1>>, [], state.services, %{})
      assert r == <<2>>
      assert length(e) == 1
    end
  end

  use Sizes

  describe "execute_work_package/3" do
    setup do
      Application.put_env(:jamixir, :pvm, MockPVM)
      stub(MockPVM, :do_authorized, fn _, _, _ -> {<<1>>, 0} end)
      stub(ErasureCodingMock, :do_erasure_code, fn _ -> [<<>>] end)

      stub(MockPVM, :do_refine, fn j, p, _, _, _, _, _ ->
        w = Enum.at(p.work_items, j)

        {<<1, 2, 3>>, List.duplicate(<<3::@export_segment_size*8>>, w.export_count), 555}
      end)

      on_exit(fn ->
        Application.put_env(:jamixir, :pvm, PVM)
      end)

      service_account =
        build(:service_account,
          preimage_storage_p: %{<<1>> => <<0, 7, 7, 7>>},
          preimage_storage_l: %{{<<1>>, 4} => [1]},
          code_hash: <<1>>
        )

      wp =
        build(:work_package,
          authorization_code_hash: service_account.code_hash,
          context: build(:refinement_context, timeslot: 3),
          work_items: build_list(1, :work_item, export_count: 1)
        )

      services = %{wp.service => service_account}
      {:ok, services: services, wp: wp}
    end

    test "smoke test", %{wp: wp, services: services} do
      task = WorkReport.execute_work_package(wp, 0, services)
      {wr, e} = Task.await(task)
      [wi | _] = wp.work_items
      assert wr.refinement_context == wp.context
      assert wr.core_index == 0
      assert wr.output == <<1>>
      assert wr.authorizer_hash == WorkPackage.implied_authorizer(wp, services)
      assert wr.specification.exports_root == MerkleTree.merkle_root(e)

      expected_work_digest = %WorkDigest{
        service: 1,
        code_hash: wi.code_hash,
        payload_hash: h(wi.payload),
        gas_ratio: wi.refine_gas_limit,
        exports: 1,
        extrinsic_count: 1,
        extrinsic_size: 7,
        gas_used: 555,
        imports: 1,
        result: <<1, 2, 3>>
      }

      assert wr.digests == [expected_work_digest]
      %AvailabilitySpecification{} = wr.specification
    end

    test "PVM return error on authorized", %{wp: wp, services: services} do
      stub(MockPVM, :do_authorized, fn _, _, _ -> {:bad, 0} end)
      task = WorkReport.execute_work_package(wp, 0, services)
      assert task == :error
    end

    test "bad exports when processing items", %{wp: wp, services: services} do
      stub(MockPVM, :do_refine, fn _, _, _, _, _, _, _ -> {:bad, [<<1>>], 555} end)
      task = WorkReport.execute_work_package(wp, 0, services)
      {wr, _e} = Task.await(task)
      [work_digest | _] = wr.digests
      assert work_digest.result == :bad
    end
  end

  describe "to_json/1" do
    test "encodes a work report to json", %{wr: wr} do
      wr = put_in(wr.segment_root_lookup, %{Hash.one() => Hash.two()})
      json = JsonEncoder.encode(wr)

      assert json == %{
               package_spec: JsonEncoder.encode(wr.specification),
               context: JsonEncoder.encode(wr.refinement_context),
               core_index: wr.core_index,
               authorizer_hash: b16(wr.authorizer_hash),
               auth_output: b16(wr.output),
               segment_root_lookup: [
                 %{
                   work_package_hash: b16(Hash.one()),
                   segment_tree_root: b16(Hash.two())
                 }
               ],
               digests: for(r <- wr.digests, do: JsonEncoder.encode(r)),
               auth_gas_used: 0
             }
    end
  end

  describe "get_segment_lookup_dict/1" do
    test "return correct lookup dictionary" do
      Storage.put_segments_root(Hash.one(), Hash.two())

      wp =
        build(:work_package,
          work_items: [
            # correct item
            build(:work_item, import_segments: [{{:tagged_hash, Hash.one()}, 7}]),
            # original segment, ignore
            build(:work_item, import_segments: [{Hash.three(), 9}]),
            # not stored segment, ignore
            build(:work_item, import_segments: [{{:tagged_hash, Hash.random()}, 7}])
          ]
        )

      assert WorkReport.get_segment_lookup_dict(wp) == %{Hash.one() => Hash.two()}
    end

    test "return empty lookup dictionary when no segments" do
      wp = build(:work_package, work_items: [])
      assert WorkReport.get_segment_lookup_dict(wp) == %{}
    end

    test "maximum 7 items in segment lookup" do
      wp_hashes = for i <- 1..10, do: <<i::hash()>>
      segments = for h <- wp_hashes, do: {{:tagged_hash, h}, 7}
      for w <- wp_hashes, do: Storage.put_segments_root(w, Hash.random())

      wp = build(:work_package, work_items: [build(:work_item, import_segments: segments)])

      assert Map.keys(WorkReport.get_segment_lookup_dict(wp)) == Enum.take(wp_hashes, 8)
    end

    test "duplicate package returns only one dict key/value" do
      wp_hash = Hash.random()
      Storage.put_segments_root(wp_hash, Hash.two())

      segments = [
        {{:tagged_hash, wp_hash}, 7},
        # two segmentes same package
        {{:tagged_hash, wp_hash}, 9}
      ]

      wp = build(:work_package, work_items: [build(:work_item, import_segments: segments)])

      assert WorkReport.get_segment_lookup_dict(wp) == %{wp_hash => Hash.two()}
    end
  end
end
