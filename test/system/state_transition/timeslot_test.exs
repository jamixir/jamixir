defmodule System.StateTransition.TimeslotTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias System.State
  alias Block.{Header}
  alias Block

  test "add_block/2 correctly sets timeslot" do
    state = %State{
      build(:genesis_state)
      | entropy_pool: %State.EntropyPool{
          current: "initial_entropy",
          history: ["eta1", "eta2", "eta3"]
        },
        timeslot: 6
    }

    block = %Block{
      header: %Header{timeslot: 7, vrf_signature: "0x00000000000"},
      extrinsic: %Block.Extrinsic{}
    }

    assert State.add_block(state, block).timeslot === 7
  end
end
