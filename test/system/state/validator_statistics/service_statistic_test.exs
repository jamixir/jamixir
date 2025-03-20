defmodule System.State.ServiceStatisticTest do
  use ExUnit.Case
  alias Block.Extrinsic.Guarantee.WorkResult
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Block.Extrinsic
  alias Block.Extrinsic.Preimage
  alias System.State.ServiceStatistic

  describe "preimage_services/1" do
    test "returns empty MapSet when extrinsic has no preimages" do
      extrinsic = %Extrinsic{preimages: []}
      result = ServiceStatistic.preimage_services(extrinsic)
      assert result == MapSet.new()
    end

    test "returns MapSet with unique services when extrinsic has multiple preimages" do
      service_ids = [123, 456, 123]
      extrinsic = %Extrinsic{preimages: for(id <- service_ids, do: %Preimage{service: id})}
      result = ServiceStatistic.preimage_services(extrinsic)
      assert result == MapSet.new(service_ids)
    end
  end

  describe "results_services/1" do
    test "returns empty MapSet when there are no work reports" do
      result = ServiceStatistic.work_results_services([])
      assert result == MapSet.new()
    end

    test "returns MapSet with unique services from work reports" do
      work_reports = [
        %WorkReport{results: [%WorkResult{service: 123}, %WorkResult{service: 456}]},
        %WorkReport{results: [%WorkResult{service: 8}]}
      ]

      result = ServiceStatistic.work_results_services(work_reports)
      assert result == MapSet.new([8, 123, 456])
    end
  end
end
