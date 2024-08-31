defmodule System.StateTransition.TimeslotTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias System.State
  alias Block.{Header}
  alias Block

  test "add_block/2 correctly sets timeslot" do
    %{state: state, validator_key_pairs: validator_key_pairs} = build(:genesis_state_with_safrole)

    {validators, key_pairs} =
      Enum.unzip(Enum.map(validator_key_pairs, fn %{validator: v, keypair: k} -> {v, k} end))

    state = %{
      state
      | timeslot: 6
    }

    block_author_key_index = rem(7, length(validators))

    header =
      System.HeaderSeal.seal_header(
        %Header{timeslot: 7, block_author_key_index: block_author_key_index},
        state.safrole.current_epoch_slot_sealers,
        state.entropy_pool,
        Enum.at(key_pairs, block_author_key_index)
      )

    block = %Block{
      header: header,
      extrinsic: %Block.Extrinsic{}
    }

    assert State.add_block(state, block).timeslot === 7
  end
end
