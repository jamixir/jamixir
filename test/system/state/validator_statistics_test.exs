defmodule System.State.ValidatorStatisticsTest do
  alias System.State.ValidatorStatistics
  use ExUnit.Case
  import Jamixir.Factory

  describe "encode/1" do
    test "encode smoke test" do
      assert Codec.Encoder.encode(build(:validator_statistics)) ==
               "\x01\0\0\0\x02\0\0\0\x03\0\0\0\x04\0\0\0\x05\0\0\0\x06\0\0\0\x01\0\0\0\x02\0\0\0\x03\0\0\0\x04\0\0\0\x05\0\0\0\x06\0\0\0\x01\0\0\0\x02\0\0\0\x03\0\0\0\x04\0\0\0\x05\0\0\0\x06\0\0\0\x01\0\0\0\x02\0\0\0\x03\0\0\0\x04\0\0\0\x05\0\0\0\x06\0\0\0"
    end
  end

  describe "posterior_validator_statistics/5" do
    setup do
      {:ok,
       %{
         current_stats: [ValidatorStatistics.statistic(1, 2, 3, 4, 5, 6)],
         previous_stats: [ValidatorStatistics.statistic(11, 12, 13, 14, 15, 16)]
       }}
    end

    test "updates previous epoch statistics when new epoc", %{
      current_stats: current_stats,
      previous_stats: previous_stats
    } do
      validator_statistics = %ValidatorStatistics{
        current_epoch_statistics: current_stats,
        previous_epoch_statistics: previous_stats
      }

      new_stats =
        ValidatorStatistics.posterior_validator_statistics(
          build(:extrinsic),
          500,
          1000,
          validator_statistics,
          build(:header)
        )

      assert new_stats.previous_epoch_statistics == current_stats
    end

    test "previous epoch statistics remains the same when same epoc", %{
      current_stats: current_stats,
      previous_stats: previous_stats
    } do
      validator_statistics = %ValidatorStatistics{
        current_epoch_statistics: current_stats,
        previous_epoch_statistics: previous_stats
      }

      new_stats =
        ValidatorStatistics.posterior_validator_statistics(
          build(:extrinsic),
          1,
          2,
          validator_statistics,
          build(:header)
        )

      assert new_stats.previous_epoch_statistics == previous_stats
    end

    test "updates author blocks produced statistics" do
      validator_statistics = build(:validator_statistics)

      non_author_blocks_produced =
        Enum.at(validator_statistics.current_epoch_statistics, 0).blocks_produced

      author_blocks_produced =
        Enum.at(validator_statistics.current_epoch_statistics, 1).blocks_produced

      new_stats =
        ValidatorStatistics.posterior_validator_statistics(
          build(:extrinsic),
          1,
          2,
          validator_statistics,
          build(:header, block_author_key_index: 1)
        )

      assert Enum.at(new_stats.current_epoch_statistics, 1).blocks_produced ==
               author_blocks_produced + 1

      assert Enum.at(new_stats.current_epoch_statistics, 0).blocks_produced ==
               non_author_blocks_produced
    end
  end
end
