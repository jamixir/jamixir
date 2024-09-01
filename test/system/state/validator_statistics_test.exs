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
          validator_statistics,
          [],
          build(:header, timeslot: 1000)
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
          validator_statistics,
          [],
          build(:header, timeslot: 2)
        )

      assert new_stats.previous_epoch_statistics == previous_stats
    end

    test "updates author blocks produced statistics" do
      validator_statistics = build(:validator_statistics)

      [non_author_blocks_produced, author_blocks_produced] =
        Enum.map(
          validator_statistics.current_epoch_statistics,
          & &1.blocks_produced
        )

      new_stats =
        ValidatorStatistics.posterior_validator_statistics(
          build(:extrinsic),
          1,
          validator_statistics,
          [],
          build(:header, block_author_key_index: 1, timeslot: 2)
        )

      assert Enum.map(new_stats.current_epoch_statistics, & &1.blocks_produced) ==
               [non_author_blocks_produced, author_blocks_produced + 1]
    end

    test "updates author tickets introduced statistics" do
      validator_statistics = build(:validator_statistics)

      [non_author_tickets_introduced, author_tickets_introduced] =
        Enum.map(
          validator_statistics.current_epoch_statistics,
          & &1.tickets_introduced
        )

      extrinsic = build(:extrinsic, tickets: build_list(3, :seal_key_ticket))

      new_stats =
        ValidatorStatistics.posterior_validator_statistics(
          extrinsic,
          1,
          validator_statistics,
          [],
          build(:header, block_author_key_index: 1, timeslot: 2)
        )

      assert Enum.map(new_stats.current_epoch_statistics, & &1.tickets_introduced) ==
               [non_author_tickets_introduced, author_tickets_introduced + 3]
    end

    test "updates author preimages introduced statistics" do
      validator_statistics = build(:validator_statistics)

      [non_author_preimages_introduced, author_preimages_introduced] =
        Enum.map(
          validator_statistics.current_epoch_statistics,
          & &1.preimages_introduced
        )

      extrinsic = build(:extrinsic, preimages: build_list(4, :preimage))

      new_stats =
        ValidatorStatistics.posterior_validator_statistics(
          extrinsic,
          1,
          validator_statistics,
          [],
          build(:header, block_author_key_index: 1, timeslot: 2)
        )

      assert Enum.map(new_stats.current_epoch_statistics, & &1.preimages_introduced) ==
               [non_author_preimages_introduced, author_preimages_introduced + 4]
    end

    test "updates author data size statistics" do
      validator_statistics = build(:validator_statistics)

      [non_author_data_size, author_data_size] =
        Enum.map(
          validator_statistics.current_epoch_statistics,
          & &1.data_size
        )

      extrinsic = build(:extrinsic, preimages: build_list(4, :preimage))

      new_stats =
        ValidatorStatistics.posterior_validator_statistics(
          extrinsic,
          1,
          validator_statistics,
          [],
          build(:header, block_author_key_index: 1, timeslot: 2)
        )

      # 20 = 4 preimages of 5 bytes
      assert Enum.map(new_stats.current_epoch_statistics, & &1.data_size) ==
               [non_author_data_size, author_data_size + 20]
    end

    test "updates author assurances statistics" do
      validator_statistics = build(:validator_statistics)

      [non_author_availability_assurances, author_availability_assurances] =
        Enum.map(
          validator_statistics.current_epoch_statistics,
          & &1.availability_assurances
        )

      extrinsic = build(:extrinsic, assurances: [build(:assurance, validator_index: 1)])

      new_stats =
        ValidatorStatistics.posterior_validator_statistics(
          extrinsic,
          1,
          validator_statistics,
          [],
          build(:header, block_author_key_index: 1, timeslot: 2)
        )

      assert Enum.map(new_stats.current_epoch_statistics, & &1.availability_assurances) ==
               [non_author_availability_assurances, author_availability_assurances + 1]
    end

    test "update assurance statistics for non authors also" do
      validator_statistics = build(:validator_statistics)

      [non_author_availability_assurances, author_availability_assurances] =
        Enum.map(
          validator_statistics.current_epoch_statistics,
          & &1.availability_assurances
        )

      extrinsic = build(:extrinsic, assurances: [build(:assurance, validator_index: 0)])

      new_stats =
        ValidatorStatistics.posterior_validator_statistics(
          extrinsic,
          1,
          validator_statistics,
          [],
          build(:header, block_author_key_index: 1, timeslot: 2)
        )

      assert Enum.map(new_stats.current_epoch_statistics, & &1.availability_assurances) ==
               [non_author_availability_assurances + 1, author_availability_assurances]
    end

    test "raise exception when there is no author statistics" do
      validator_statistics = build(:validator_statistics)

      assert_raise ArgumentError, "Author statistics not found", fn ->
        ValidatorStatistics.posterior_validator_statistics(
          build(:extrinsic),
          0,
          validator_statistics,
          [],
          build(:header, block_author_key_index: 1000)
        )
      end
    end
  end
end
