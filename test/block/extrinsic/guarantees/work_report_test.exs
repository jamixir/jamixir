defmodule WorkReportTest do
  use ExUnit.Case
  import Jamixir.Factory
  import TestHelper
  alias Block.Extrinsic.Guarantee.WorkReport
  alias System.State.Ready
  alias Util.Hash

  setup do
    {:ok,
     wr:
       build(:work_report,
         specification: build(:availability_specification, work_package_hash: Hash.one())
       )}
  end

  describe "encode/1" do
    test "encode/1 smoke test", %{wr: wr} do
      assert Codec.Encoder.encode(wr) ==
               "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\x02\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x03\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x03\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04\x05\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\x01\x03\x02\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\x03\0\0\0\0\0\0\0\0\x01\x04\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\x03\0\0\0\0\0\0\0\0\x01\x04"
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
          segment_root_lookup: for(i <- 1..9, into: %{}, do: {<<i::256>>, <<i::256>>})
        )

      refute WorkReport.valid_size?(invalid_wr)
    end

    test "returns false when encoded size exceeds max_work_report_size" do
      large_output = String.duplicate("a", Constants.max_work_report_size())
      invalid_wr = build(:work_report, output: large_output, segment_root_lookup: %{})
      refute WorkReport.valid_size?(invalid_wr)
    end
  end

  describe "available_work_reports/2" do
    setup_constants do
      def validator_count, do: 6
      def core_count, do: 2
    end

    setup do
      # Create mock assurances using factory
      # 6 validators / 2 cores
      assurances = [
        build(:assurance, bitfield: <<0b10::2>>),
        build(:assurance, bitfield: <<0b10::2>>),
        build(:assurance, bitfield: <<0b10::2>>),
        build(:assurance, bitfield: <<0b11::2>>),
        build(:assurance, bitfield: <<0b11::2>>),
        build(:assurance, bitfield: <<0b00::2>>)
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
      assert for(x <- result, do: x.core_index) == [0]
    end

    test "returns empty list when no cores have sufficient assurances" do
      assurances = for _ <- 1..6, do: build(:assurance, bitfield: <<0b00::2>>)
      result = WorkReport.available_work_reports(assurances, [])
      assert result == []
    end

    test "handles case when all cores have sufficient assurances", %{core_reports: core_reports} do
      assurances = for _ <- 1..6, do: build(:assurance, bitfield: <<0b11::2>>)
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
      w1 = build(:work_report, refinement_context: %{prerequisite: nil}, segment_root_lookup: %{})

      w2 =
        build(:work_report,
          refinement_context: %{prerequisite: Hash.one()},
          segment_root_lookup: %{}
        )

      w3 = build(:work_report, refinement_context: %{prerequisite: nil}, segment_root_lookup: %{})

      w4 =
        build(:work_report,
          refinement_context: %{prerequisite: Hash.two()},
          segment_root_lookup: %{}
        )

      w5 =
        build(:work_report,
          refinement_context: %{prerequisite: Hash.three()},
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
          refinement_context: %{prerequisite: Hash.one()},
          segment_root_lookup: %{}
        )

      w2 =
        build(:work_report,
          refinement_context: %{prerequisite: Hash.two()},
          segment_root_lookup: %{}
        )

      {w_bang, w_q} = WorkReport.separate_work_reports([w1, w2], %{})

      assert w_bang == []
      assert [^w1, ^w2] = Enum.map(w_q, fn {wr, _deps} -> wr end)
    end

    test "handles list with only non-prerequisites" do
      w1 = build(:work_report, refinement_context: %{prerequisite: nil}, segment_root_lookup: %{})
      w2 = build(:work_report, refinement_context: %{prerequisite: nil}, segment_root_lookup: %{})

      {w_bang, w_q} = WorkReport.separate_work_reports([w1, w2], %{})

      assert w_bang == [w1, w2]
      assert w_q == []
    end

    test "handles work reports with non-empty segment_root_lookup" do
      w1 =
        build(:work_report,
          refinement_context: %{prerequisite: nil},
          segment_root_lookup: %{Hash.one() => Hash.two()}
        )

      w2 = build(:work_report, refinement_context: %{prerequisite: nil}, segment_root_lookup: %{})

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
          refinement_context: %{prerequisite: Hash.one()},
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
      x = %{Hash.two() => Hash.five()}

      result = WorkReport.edit_queue(r, x)
      assert [{^w1, empty_set}] = result
      assert MapSet.equal?(empty_set, MapSet.new())
    end

    test "handles empty queue" do
      assert [] == WorkReport.edit_queue([], %{Hash.one() => Hash.two()})
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
      x = %{Hash.one() => Hash.five()}

      result = WorkReport.edit_queue(r, x)

      assert [{^w2, _}] = result
    end

    test "filters out work reports with conflicting segment root lookups" do
      w1 =
        build(:work_report,
          specification: %{work_package_hash: Hash.one()},
          segment_root_lookup: %{Hash.three() => Hash.four()}
        )

      w2 =
        build(:work_report,
          specification: %{work_package_hash: Hash.two()},
          segment_root_lookup: %{Hash.four() => Hash.five()}
        )

      r = [
        {w1, MapSet.new()},
        {w2, MapSet.new()}
      ]

      # Doesn't conflict with work package hashes
      # but conflicts with segment root lookup of w2
      x = %{Hash.four() => Hash.four()}

      result = WorkReport.edit_queue(r, x)

      assert [{^w1, _}] = result
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
      a = %{}

      assert [^w1] = WorkReport.accumulation_priority_queue(r, a)
    end
  end

  describe "accumulatable_work_reports/4" do
    setup do
      work_reports =
        for i <- 1..4 do
          build(:work_report,
            core_index: i,
            specification: %{work_package_hash: <<i::256>>, exports_root: <<i::256>>},
            refinement_context: %{prerequisite: nil},
            segment_root_lookup: %{}
          )
        end

      [w1, w2, w3, w4] = work_reports

      # Modify w2 to have a prerequisite or non-empty segment_root_lookup
      w2 = %{
        w2
        | refinement_context: %{prerequisite: Hash.one()},
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

      assert [^w1, ^w3, ^w4] = result
    end
  end

  @size Constants.wswe() * 8
  describe "paged_proofs/2" do
    test "paged proof smoke test" do
      bytes = for _ <- 1..10, do: <<7::@size>>
      proofs = WorkReport.paged_proofs(bytes)
      assert length(proofs) == 2
    end

    test "paged proof empty bytestring" do
      proofs = WorkReport.paged_proofs([])
      assert length(proofs) == 1
      assert Enum.all?(proofs, &(byte_size(&1) == Constants.wswe()))
    end
  end
end
