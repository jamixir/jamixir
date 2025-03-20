defmodule System.State.ValidatorStatisticsTest do
  alias Codec.JsonEncoder
  alias System.State.ValidatorStatistics
  use ExUnit.Case
  import Jamixir.Factory

  describe "encode/1" do
    test "encode smoke test" do
      assert Codec.Encoder.encode(build(:validator_statistics, count: 2)) ==
               "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x06\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x06\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x06\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x06\0\0\0"
    end
  end

  describe "transition/5" do
    setup do
      {:ok,
       %{
         current_stats: [
           %System.State.ValidatorStatistic{
             blocks_produced: 1,
             tickets_introduced: 2,
             preimages_introduced: 3,
             data_size: 4,
             reports_guaranteed: 5,
             availability_assurances: 6
           }
         ],
         previous_stats: [
           %System.State.ValidatorStatistic{
             blocks_produced: 11,
             tickets_introduced: 12,
             preimages_introduced: 13,
             data_size: 14,
             reports_guaranteed: 15,
             availability_assurances: 16
           }
         ]
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

      {:ok, validator_stats_} =
        ValidatorStatistics.transition(
          build(:extrinsic),
          500,
          validator_statistics,
          [],
          build(:header, timeslot: 1000),
          MapSet.new()
        )

      assert validator_stats_.previous_epoch_statistics == current_stats
    end

    test "previous epoch statistics remains the same when same epoc", %{
      current_stats: current_stats,
      previous_stats: previous_stats
    } do
      validator_statistics = %ValidatorStatistics{
        current_epoch_statistics: current_stats,
        previous_epoch_statistics: previous_stats
      }

      {:ok, validator_stats_} =
        ValidatorStatistics.transition(
          build(:extrinsic),
          1,
          validator_statistics,
          [],
          build(:header, timeslot: 2),
          MapSet.new()
        )

      assert validator_stats_.previous_epoch_statistics == previous_stats
    end

    test "updates author blocks produced statistics" do
      validator_statistics = build(:validator_statistics)
      author_key_index = 1

      initial_blocks_produced =
        for s <- validator_statistics.current_epoch_statistics, do: s.blocks_produced

      {:ok, validator_stats_} =
        ValidatorStatistics.transition(
          build(:extrinsic),
          1,
          validator_statistics,
          [],
          build(:header, block_author_key_index: 1, timeslot: 2),
          MapSet.new()
        )

      updated_blocks_produced =
        for s <- validator_stats_.current_epoch_statistics, do: s.blocks_produced

      assert Enum.with_index(updated_blocks_produced) ==
               Enum.with_index(initial_blocks_produced)
               |> Enum.map(fn
                 {blocks, ^author_key_index} -> {blocks + 1, author_key_index}
                 {blocks, idx} -> {blocks, idx}
               end)
    end

    test "updates author tickets introduced statistics" do
      validator_statistics = build(:validator_statistics)
      extrinsic = build(:extrinsic, tickets: build_list(3, :seal_key_ticket))
      author_key_index = 1

      initial_tickets_introduced =
        for s <- validator_statistics.current_epoch_statistics, do: s.tickets_introduced

      {:ok, validator_stats_} =
        ValidatorStatistics.transition(
          extrinsic,
          author_key_index,
          validator_statistics,
          [],
          build(:header, block_author_key_index: author_key_index, timeslot: 2),
          MapSet.new()
        )

      assert Enum.with_index(
               validator_stats_.current_epoch_statistics,
               fn %{tickets_introduced: tickets}, idx ->
                 if idx == author_key_index,
                   do: tickets == Enum.at(initial_tickets_introduced, idx) + 3,
                   else: tickets == Enum.at(initial_tickets_introduced, idx)
               end
             )
    end

    test "updates author preimages introduced statistics" do
      validator_statistics = build(:validator_statistics)
      extrinsic = build(:extrinsic, preimages: build_list(4, :preimage))
      author_key_index = 1

      initial_preimages_introduced =
        for s <- validator_statistics.current_epoch_statistics, do: s.preimages_introduced

      {:ok, validator_stats_} =
        ValidatorStatistics.transition(
          extrinsic,
          author_key_index,
          validator_statistics,
          [],
          build(:header, block_author_key_index: author_key_index, timeslot: 2),
          MapSet.new()
        )

      assert Enum.with_index(
               validator_stats_.current_epoch_statistics,
               fn %{preimages_introduced: preimages}, idx ->
                 if idx == author_key_index,
                   do: preimages == Enum.at(initial_preimages_introduced, idx) + 4,
                   else: preimages == Enum.at(initial_preimages_introduced, idx)
               end
             )
    end

    test "updates author data size statistics" do
      validator_statistics = build(:validator_statistics)
      extrinsic = build(:extrinsic, preimages: build_list(4, :preimage))
      author_key_index = 1

      initial_data_size = for s <- validator_statistics.current_epoch_statistics, do: s.data_size

      {:ok, validator_stats_} =
        ValidatorStatistics.transition(
          extrinsic,
          author_key_index,
          validator_statistics,
          [],
          build(:header, block_author_key_index: author_key_index, timeslot: 2),
          MapSet.new()
        )

      assert Enum.with_index(
               validator_stats_.current_epoch_statistics,
               fn %{data_size: size}, idx ->
                 if idx == author_key_index,
                   do: size == Enum.at(initial_data_size, idx) + 20,
                   else: size == Enum.at(initial_data_size, idx)
               end
             )
    end

    test "updates author assurances statistics" do
      validator_statistics = build(:validator_statistics)
      extrinsic = build(:extrinsic, assurances: [build(:assurance, validator_index: 1)])
      author_key_index = 1

      initial_availability_assurances =
        for s <- validator_statistics.current_epoch_statistics, do: s.availability_assurances

      {:ok, validator_stats_} =
        ValidatorStatistics.transition(
          extrinsic,
          author_key_index,
          validator_statistics,
          [],
          build(:header, block_author_key_index: author_key_index, timeslot: 2),
          MapSet.new()
        )

      assert Enum.with_index(
               validator_stats_.current_epoch_statistics,
               fn %{availability_assurances: assurances}, idx ->
                 if idx == author_key_index,
                   do: assurances == Enum.at(initial_availability_assurances, idx) + 1,
                   else: assurances == Enum.at(initial_availability_assurances, idx)
               end
             )
    end

    test "return same stats when there is no author statistics" do
      validator_statistics = build(:validator_statistics)

      {:error, msg} =
        ValidatorStatistics.transition(
          build(:extrinsic),
          0,
          validator_statistics,
          [],
          build(:header, block_author_key_index: 1000),
          MapSet.new()
        )

      assert msg == :author_stats_not_found
    end
  end

  describe "to_json/1" do
    test "encodes a validator statistics to json" do
      vs = build(:validator_statistics)
      json = JsonEncoder.encode(vs)

      core_stat = %{
        data_size: 0,
        p: 0,
        bundle_length: 0,
        exported_segments: 0,
        extrinsics_count: 0,
        extrinsics_size: 0,
        imported_segments: 0,
        refine_gas: 0
      }

      assert json == %{
               current: for(s <- vs.current_epoch_statistics, do: JsonEncoder.encode(s)),
               last: for(s <- vs.previous_epoch_statistics, do: JsonEncoder.encode(s)),
               core_statistics: for(_ <- 1..Constants.core_count(), do: core_stat)
             }
    end
  end
end
