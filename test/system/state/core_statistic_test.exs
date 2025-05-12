defmodule System.State.CoreStatisticTest do
  alias System.State.CoreStatistic
  import Jamixir.Factory

  use ExUnit.Case

  describe "calculate_core_statistics/1" do
    setup do
      digest =
        build(:work_digest,
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
          digests: [digest, digest]
        )

      {:ok, work_report: work_report}
    end

    test "calculate_core_statistics smoke test", %{work_report: wr} do
      work_reports = [wr, nil]
      assurances = []
      stat = CoreStatistic.calculate_core_statistics(work_reports, work_reports, assurances)

      assert stat == [
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
               %CoreStatistic{}
             ]
    end
  end
end
