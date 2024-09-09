defmodule System.StateTransition.TimeslotTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias System.State
  alias Block.{Header}
  alias Block

  test "add_block/2 correctly sets timeslot" do
    %{state: state, validators: validators, key_pairs: key_pairs} =
      build(:genesis_state_with_safrole)

    state = %{
      state
      | timeslot: 6
    }

    block =
      build(:safrole_block,
        state: state,
        timeslot: 7,
        key_pairs: key_pairs,
        block_author_key_index: 1
      )

    assert State.add_block(state, block).timeslot === 7
  end
end
