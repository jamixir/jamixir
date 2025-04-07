defmodule System.State.CoreReportTest do
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Codec.JsonEncoder
  alias System.State.CoreReport
  alias Util.Hash
  use ExUnit.Case
  import Jamixir.Factory
  import OriginalModules
  use Codec.Encoder

  describe "encode/1" do
    test "encode core report smoke test" do
      core_report = build(:core_report)

      assert e(core_report) == e(core_report.work_report) <> e_le(core_report.timeslot, 4)
    end
  end

  describe "initial_core_reports/0" do
    test "initial_core_reports smoke test" do
      assert length(CoreReport.initial_core_reports()) == Constants.core_count()
      assert CoreReport.initial_core_reports() |> Enum.all?(&is_nil/1)
    end
  end

  describe "process_disputes/2" do
    setup do
      cr1 = build(:core_report)
      cr2 = build(:core_report, work_report: build(:work_report, core_index: 2))
      %{cr1: cr1, cr2: cr2, core_reports: [cr1, cr2]}
    end

    test "removes disputed reports", %{cr1: cr1, cr2: cr2, core_reports: crs} do
      assert CoreReport.process_disputes(crs, [Hash.default(e(cr1.work_report))]) == [nil, cr2]
    end

    test "keeps undisputed reports", %{core_reports: crs} do
      assert CoreReport.process_disputes(crs, [Hash.default("other_hash")]) == crs
    end

    test "handles empty bad_wonky_verdicts", %{core_reports: crs} do
      assert CoreReport.process_disputes(crs, []) == crs
    end

    test "handles all reports disputed", %{cr1: cr1, cr2: cr2, core_reports: crs} do
      bad_wonky_verdicts = for c <- [cr1, cr2], do: Hash.default(e(c.work_report))
      assert CoreReport.process_disputes(crs, bad_wonky_verdicts) == [nil, nil]
    end
  end

  describe "transition/4" do
    test "transition smoke test" do
      core_reports = [nil, nil]
      guarantees = []

      assert core_reports == CoreReport.transition(core_reports, guarantees, 0)
    end

    test "add new work report in guarantees to core reports" do
      core_reports = [nil, nil]
      w = build(:work_report, core_index: 0)
      guarantees = [build(:guarantee, work_report: w)]

      assert [c0, c1] =
               CoreReport.transition(core_reports, guarantees, 7)

      assert c0.work_report == w
      assert c0.timeslot == 7
      assert is_nil(c1)
    end

    test "core reports remain unchanged when no guarantees" do
      core_reports = [nil, nil]
      guarantees = []

      assert core_reports ==
               CoreReport.transition(core_reports, guarantees, 0)
    end
  end

  describe "process_availability/4" do
    test "use core reports intermediate when no core reports is member of W" do
      core_reports = build_list(3, :core_report)
      i_core_reports = build_list(3, :core_report, timeslot: 0)

      limit_timelot = Constants.unavailability_period() - 1

      with_original_modules([:process_availability]) do
        assert CoreReport.process_availability(core_reports, i_core_reports, [], limit_timelot)
               |> Enum.take(3) == i_core_reports
      end
    end

    test "core reports nil when member of W" do
      core_reports = build_list(2, :core_report)
      assurances = build_list(6, :assurance, bitfield: <<255>>)
      available_work_reports = WorkReport.available_work_reports(assurances, core_reports)

      with_original_modules([:process_availability, :available_work_reports]) do
        assert CoreReport.process_availability(core_reports, core_reports, available_work_reports, 0) ==
                 [nil, nil]
      end
    end

    test "core reports nil when expired" do
      core_reports = build_list(2, :core_report, timeslot: 0)
      expired_time = 0 + Constants.unavailability_period()

      with_original_modules([:process_availability, :available_work_reports]) do
        assert CoreReport.process_availability(core_reports, core_reports, [], expired_time) ==
                 [nil, nil]
      end
    end

    test "core reports nil when intermediate are nil" do
      core_reports = build_list(2, :core_report, timeslot: 0)

      with_original_modules([:process_availability, :available_work_reports]) do
        assert CoreReport.process_availability(core_reports, [nil, nil], [], 0) ==
                 [nil, nil]
      end
    end

    test "process availability when core reports are  nil returns nil" do
      core_reports = [nil, nil, nil]
      i_core_reports = build_list(3, :core_report)

      with_original_modules([:process_availability]) do
        assert CoreReport.process_availability(core_reports, i_core_reports, [], 0) ==
                 core_reports
      end
    end
  end

  describe "from_json/1" do
    test "return nil when json is null" do
      assert CoreReport.from_json(nil) == nil
    end
  end

  describe "to_json/1" do
    test "encodes a core report to json" do
      cr = build(:core_report)

      assert JsonEncoder.encode(cr) == %{
               report: JsonEncoder.encode(cr.work_report),
               timeout: cr.timeslot
             }
    end
  end
end
