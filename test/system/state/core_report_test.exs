defmodule System.State.CoreReportTest do
  alias Codec.Encoder
  alias System.State.CoreReport
  alias Util.Hash
  use ExUnit.Case
  import Jamixir.Factory
  import OriginalModules

  describe "encode/1" do
    test "encode core report smoke test" do
      core_report = build(:core_report)

      assert Codec.Encoder.encode(core_report) ==
               Codec.Encoder.encode(core_report.work_report) <>
                 Codec.Encoder.encode_le(core_report.timeslot, 4)
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
      assert CoreReport.process_disputes(crs, [Hash.default(Encoder.encode(cr1.work_report))]) ==
               [nil, cr2]
    end

    test "keeps undisputed reports", %{core_reports: crs} do
      assert CoreReport.process_disputes(crs, [Hash.default("other_hash")]) == crs
    end

    test "handles empty bad_wonky_verdicts", %{core_reports: crs} do
      assert CoreReport.process_disputes(crs, []) == crs
    end

    test "handles all reports disputed", %{cr1: cr1, cr2: cr2, core_reports: crs} do
      bad_wonky_verdicts = Enum.map([cr1, cr2], &Hash.default(Encoder.encode(&1.work_report)))
      assert CoreReport.process_disputes(crs, bad_wonky_verdicts) == [nil, nil]
    end
  end

  describe "calculate_core_reports_/4" do
    test "calculate_core_reports_ smoke test" do
      core_reports = [build(:core_report)]
      guarantees = [build(:guarantee)]

      assert {:ok, core_reports} ==
               CoreReport.calculate_core_reports_(core_reports, guarantees, 0)
    end

    test "add new work report in guarantees to core reports" do
      core_reports = [nil, nil]
      w = build(:work_report, core_index: 0)
      guarantees = [build(:guarantee, work_report: w)]

      assert {:ok, [c0, c1]} =
               CoreReport.calculate_core_reports_(core_reports, guarantees, 7)

      assert c0.work_report == w
      assert c0.timeslot == 7
      assert is_nil(c1)
    end

    test "core reports remain unchanged when no guarantees" do
      core_reports = [nil, nil]
      guarantees = []

      assert {:ok, core_reports} ==
               CoreReport.calculate_core_reports_(core_reports, guarantees, 0)
    end

    test "return error when report sizes are invalid" do
      core_reports = [build(:core_report)]

      guarantee =
        build(:guarantee,
          work_report:
            build(:work_report,
              output: "a" <> String.duplicate("b", Constants.max_work_report_size())
            )
        )

      assert {:error, :invalid_work_report_size} ==
               CoreReport.calculate_core_reports_(core_reports, [guarantee], 0)
    end
  end

  describe "process_availability/3" do
    test "use core reports intermediate when no core reports is member of W" do
      # random core reports
      core_reports = build_list(3, :core_report)
      # random core reports intermediate
      i_core_reports = build_list(3, :core_report)

      with_original_modules([:process_availability]) do
        assert CoreReport.process_availability(core_reports, i_core_reports, [])
               |> Enum.take(3) == i_core_reports
      end
    end
  end
end
