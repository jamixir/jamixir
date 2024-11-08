defmodule TestnetBlockImporterTest do
  alias System.State
  import TestVectorUtil
  use ExUnit.Case, async: false

  @traces_path "traces/safrole/"

  describe "test blocks and states" do
    @tag :skip
    test "jam-dune" do
      {:ok, genesis_json} =
        fetch_and_parse_json("genesis.json", @traces_path, "jamixir", "jamtestnet")

      state = State.from_json(genesis_json)

      for epoch <- 349_445..349_449 do
        for timeslot <- 0..11 do
          block_bin =
            fetch_binary(
              "#{epoch}_#{timeslot}.bin",
              "#{@traces_path}jam_duna/blocks/",
              "jamixir",
              "jamtestnet"
            )

          {block, _} = Block.decode(block_bin)

          {:ok, expected_state_json} =
            fetch_and_parse_json(
              "#{epoch}_#{timeslot}.json",
              "#{@traces_path}jam_duna/state_snapshots/",
              "jamixir",
              "jamtestnet"
            )

          expected_state = State.from_json(expected_state_json)
          state = State.add_block(state, block)
          assert expected_state == state
        end
      end

      assert state.timeslot == 0
    end
  end
end
