defmodule System.StateTest do
  use ExUnit.Case

  alias System.State
  alias Block.Header

  test "add_block/1 correctly set timeslot" do
    state = %State{}
    block = %Block{header: %Header{timeslot: 7}, extrinsic: %Block.Extrinsic{}}

    assert State.add_block(state, block).timeslot === 7
  end
end
