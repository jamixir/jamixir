defmodule TestnetBlockImporterTest do
  alias IO.ANSI
  alias System.State
  import TestVectorUtil
  use ExUnit.Case, async: false

  @traces_path "traces/safrole/"

  @last_epoch 349_449
  @first_epoch 349_445

  setup_all do
    RingVrf.init_ring_context(Constants.validator_count())
    :ok
  end

  describe "test blocks and states" do
    # waiting for correctnes of other party side
    @tag :skip
    test "jam-dune" do
      {:ok, genesis_json} =
        fetch_and_parse_json("genesis.json", @traces_path, "jamixir", "jamtestnet")

      state = State.from_json(genesis_json)

      for epoch <- @first_epoch..@last_epoch do
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
          # IO.inspect(State.serialize_hex(state))

          case State.add_block(state, block) do
            {:ok, state} ->
              for field <- Utils.list_struct_fields(System.State) do
                assert Map.get(expected_state, field) == Map.get(state, field)
              end

            {:error, _, error} ->
              assert false,
                     "Error in block jam_duna #{epoch}:#{timeslot}\n#{ANSI.yellow()}#{error}"
          end
        end
      end
    end
  end
end
