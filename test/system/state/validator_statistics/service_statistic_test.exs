defmodule System.State.ServiceStatisticTest do
  use ExUnit.Case
  alias Block.Extrinsic.Guarantee.WorkResult
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Block.Extrinsic
  alias Block.Extrinsic.Preimage
  alias System.State.ServiceStatistic

  describe "calculate_stats/4" do
    test "returns empty map when no inputs" do
      result = ServiceStatistic.calculate_stats([], [], [], [])
      assert result == %{}
    end

    test "integrates all statistics correctly" do
      available_work_reports = [
        %WorkReport{
          results: [
            %WorkResult{
              service: 1,
              imports: 5,
              extrinsic_count: 10,
              extrinsic_size: 1000,
              exports: 2,
              gas_used: 500
            }
          ]
        }
      ]

      accumulation_stats = %{1 => {800, 3}}
      deferred_transfers_stats = %{1 => {2, 200}}

      preimages = [%Preimage{service: 1, blob: <<1, 2, 3, 4>>}]

      result =
        ServiceStatistic.calculate_stats(
          available_work_reports,
          accumulation_stats,
          deferred_transfers_stats,
          preimages
        )

      assert result[1] == %ServiceStatistic{
               refine: {1, 500},
               imports: 5,
               extrinsic_count: 10,
               extrinsic_size: 1000,
               exports: 2,
               accumulation: {800, 3},
               transfers: {2, 200},
               preimage: {1, 4}
             }
    end
  end

  describe "refine_stats/1 (private function test)" do
    test "correctly aggregates refine-related statistics" do
      available_work_reports = [
        %WorkReport{
          results: [
            %WorkResult{
              service: 1,
              imports: 5,
              extrinsic_count: 10,
              extrinsic_size: 1000,
              exports: 2,
              gas_used: 500
            },
            %WorkResult{
              # Same service to test aggregation
              service: 1,
              imports: 3,
              extrinsic_count: 5,
              extrinsic_size: 500,
              exports: 1,
              gas_used: 300
            },
            %WorkResult{
              # Different service
              service: 2,
              imports: 1,
              extrinsic_count: 2,
              extrinsic_size: 200,
              exports: 0,
              gas_used: 100
            }
          ]
        }
      ]

      result = ServiceStatistic.calculate_stats(available_work_reports, [], [], [])

      assert map_size(result) == 2

      assert result[1] == %ServiceStatistic{
               imports: 8,
               extrinsic_count: 15,
               extrinsic_size: 1500,
               exports: 3,
               refine: {2, 800}
             }

      assert result[2] == %ServiceStatistic{
               imports: 1,
               extrinsic_count: 2,
               extrinsic_size: 200,
               exports: 0,
               refine: {1, 100}
             }
    end
  end

  describe "accumulation_stats/2 (private function test)" do
    test "correctly adds accumulation statistics" do
      accumulation_stats = [{1, {300, 2}}, {3, {400, 3}}]

      result = ServiceStatistic.calculate_stats([nil, nil], accumulation_stats, [], [])

      assert result[1].accumulation == {300, 2}
      assert result[3].accumulation == {400, 3}
    end
  end

  describe "deferred_transfers_stats/2 (private function test)" do
    test "correctly adds deferred transfer statistics" do
      deferred_transfers_stats = %{1 => {2, 200}, 4 => {3, 300}}

      result = ServiceStatistic.calculate_stats([], [], deferred_transfers_stats, [])

      assert result[1].transfers == {2, 200}
      assert result[4].transfers == {3, 300}
    end
  end

  describe "preimage_stats/2 (private function test)" do
    test "correctly adds preimage statistics" do
      preimages = [
        %Preimage{service: 1, blob: <<1, 2, 3, 4>>},
        %Preimage{service: 1, blob: <<5, 6>>},
        %Preimage{service: 5, blob: <<7, 8, 9>>}
      ]

      result = ServiceStatistic.calculate_stats([], [], [], preimages)

      assert result[1].preimage == {2, 6}
      assert result[5].preimage == {1, 3}
    end
  end

  describe "full calculation with multiple services" do
    test "aggregates stats correctly for multiple services" do
      available_work_reports = [
        %WorkReport{
          results: [
            %WorkResult{
              service: 1,
              imports: 5,
              extrinsic_count: 10,
              extrinsic_size: 1000,
              exports: 2,
              gas_used: 500
            },
            %WorkResult{
              service: 2,
              imports: 1,
              extrinsic_count: 2,
              extrinsic_size: 200,
              exports: 0,
              gas_used: 100
            }
          ]
        }
      ]

      accumulation_stats = [{1, {300, 2}}, {3, {400, 3}}]
      deferred_transfers_stats = [{1, {2, 200}}, {4, {3, 300}}]

      preimages = [
        %Preimage{service: 1, blob: <<1, 2, 3, 4>>},
        %Preimage{service: 5, blob: <<7, 8, 9>>}
      ]

      result =
        ServiceStatistic.calculate_stats(
          available_work_reports,
          accumulation_stats,
          deferred_transfers_stats,
          preimages
        )

      assert map_size(result) == 5

      # Service 1 (present in all stat types)
      assert result[1] == %ServiceStatistic{
               refine: {1, 500},
               imports: 5,
               extrinsic_count: 10,
               extrinsic_size: 1000,
               exports: 2,
               accumulation: {300, 2},
               transfers: {2, 200},
               preimage: {1, 4}
             }

      # Service 2 (only in work reports)
      assert result[2].refine == {1, 100}
      assert result[2].accumulation == {0, 0}
      assert result[2].transfers == {0, 0}
      assert result[2].preimage == {0, 0}

      # Service 3 (only in accumulation stats)
      assert result[3].refine == {0, 0}
      assert result[3].accumulation == {400, 3}
      assert result[3].transfers == {0, 0}
      assert result[3].preimage == {0, 0}

      # Service 4 (only in deferred transfers)
      assert result[4].refine == {0, 0}
      assert result[4].accumulation == {0, 0}
      assert result[4].transfers == {3, 300}
      assert result[4].preimage == {0, 0}

      # Service 5 (only in preimages)
      assert result[5].refine == {0, 0}
      assert result[5].accumulation == {0, 0}
      assert result[5].transfers == {0, 0}
      assert result[5].preimage == {1, 3}
    end
  end
end
