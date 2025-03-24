defmodule System.State.CoreStatisticTest do
  alias System.State.CoreStatistic
  import Jamixir.Factory

  use ExUnit.Case

  describe "calculate_core_statistics/1" do
    setup do
      result =
        build(:work_result,
          imports: 1,
          exports: 2,
          extrinsic_count: 3,
          extrinsic_size: 4,
          gas_used: 5
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
                 imports: 2,
                 exports: 4,
                 extrinsic_count: 6,
                 extrinsic_size: 8,
                 gas_used: 10,
                 bundle_size: 7,
                 # 7 + 4104 * ⌈(2 * (65 / 64))⌉
                 da_load: 12_319
               },
               %CoreStatistic{},
               %CoreStatistic{}
             ]
    end
  end
end
