defmodule System.State.CoreStatisticTest do
  alias System.State.CoreStatistic
  import Jamixir.Factory

  use ExUnit.Case

  describe "calculate_core_statistics/1" do
    setup do
      result =
        build(:work_result,
          imported_segments: 1,
          exported_segments: 2,
          extrinsics_count: 3,
          extrinsics_size: 4,
          refine_gas: 5
        )

      specification = build(:availability_specification, length: 7)

      work_report =
        build(:work_report,
          specification: specification,
          results: [result, result]
        )

      {:ok, work_report: work_report}
    end

    test "calculate_core_statistics smoke test", %{work_report: wr} do
      available_work_reports = [wr, nil, nil]
      assurances = []

      assert CoreStatistic.calculate_core_statistics(available_work_reports, assurances) == [
               %CoreStatistic{
                 imported_segments: 2,
                 exported_segments: 4,
                 extrinsics_count: 6,
                 extrinsics_size: 8,
                 refine_gas: 10,
                 bundle_length: 7,
                 # 7 + 4104 * ⌈(2 * (65 / 64))⌉
                 data_size: 12_319
               },
               %CoreStatistic{},
               %CoreStatistic{}
             ]
    end
  end
end
