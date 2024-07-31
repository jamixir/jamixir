defmodule System.StateTest do
  use ExUnit.Case

  alias System.State
  alias Block.Header
  alias Util.Hash

  test "add_block/1 correctly set timeslot" do
    state = %State{
      entropy_pool: %EntropyPool{current: "initial_entropy", history: ["eta1", "eta2", "eta3"]},
      timeslot: 6,
    }
    block = %Block{header: %Header{timeslot: 7, vrf_signature: "0x00000000000"}, extrinsic: %Block.Extrinsic{}}



    assert State.add_block(state, block).timeslot === 7
  end

  describe "update_entropy_pool/3" do
    test "updates entropy with new VRF output" do
      header = %Header{vrf_signature: "sample_vrf_signature", timeslot: 10}
      initial_state = %EntropyPool{current: "initial_entropy", history: ["eta1", "eta2", "eta3"]}
      timeslot = 9

      updated_state = State.update_entropy_pool(header, timeslot, initial_state)

      assert updated_state.current != initial_state.current
      # Blake2b hash output size
      assert byte_size(updated_state.current) == 32

      # Calculate expected entropy
      expected_entropy = Hash.blake2b_256(initial_state.current <> State.entropy_vrf(header.vrf_signature))

      # Assert that the current entropy matches the expected value
      assert updated_state.current == expected_entropy
    end

    test "rotates entropy history on new epoch" do
      header = %Header{vrf_signature: "sample_vrf_signature", timeslot: 600}
      initial_state = %EntropyPool{current: "initial_entropy", history: ["eta1", "eta2", "eta3"]}
      timeslot = 599

      updated_state = State.update_entropy_pool(header, timeslot, initial_state)

      # Check that the history has been updated correctly
      assert hd(updated_state.history) == updated_state.current
      assert Enum.at(updated_state.history, 1) == "eta1"
      assert Enum.at(updated_state.history, 2) == "eta2"
      assert length(updated_state.history) == 3
    end

    test "does not rotate entropy history within same epoch" do
      header = %Header{vrf_signature: "sample_vrf_signature", timeslot: 602}
      initial_state = %EntropyPool{current: "initial_entropy", history: ["eta1", "eta2", "eta3"]}
      timeslot = 601

      updated_state = State.update_entropy_pool(header, timeslot, initial_state)

      assert updated_state.history == initial_state.history
    end
  end
end
