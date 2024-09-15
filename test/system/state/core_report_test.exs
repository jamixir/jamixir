defmodule System.State.CoreReportTest do
  alias Block.Extrinsic.Guarantee.WorkReport
  alias System.State.CoreReport
  use ExUnit.Case
  import Jamixir.Factory

  describe "encode/1" do
    test "encode core report smoke test" do
      core_report = build(:core_report)

      assert Codec.Encoder.encode(core_report) ==
               Codec.Encoder.encode(core_report.work_report) <>
                 Codec.Encoder.encode_le(core_report.timeslot, 4)
    end
  end

  describe "posterior_core_reports/4" do
    test "posterior_core_report smoke test" do
      core_reports = [build(:core_report)]
      guarantees = [build(:guarantee)]

      assert {:ok, core_reports} ==
               CoreReport.posterior_core_reports(core_reports, guarantees, [], 0)
    end

    test "return error when report sizes are invalid" do
      core_reports = [build(:core_report)]

      guarantee =
        build(:guarantee,
          work_report:
            build(:work_report, output: "a" <> String.duplicate("b", WorkReport.max_size()))
        )

      assert {:error, :invalid_work_report_size} ==
               CoreReport.posterior_core_reports(core_reports, [guarantee], [], 0)
    end
  end
end
