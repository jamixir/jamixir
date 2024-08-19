defmodule System.State.CoreReportTest do
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
end
