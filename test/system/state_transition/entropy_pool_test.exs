defmodule System.StateTransition.EntropyPoolTest do
  use ExUnit.Case

  alias System.State.EntropyPool
  alias Block.{Header}
  alias Util.Hash

  test "updates entropy with new VRF output" do
    header = %Header{vrf_signature: "sample_vrf_signature", timeslot: 10}
    initial_state = %EntropyPool{current: "initial_entropy", history: ["eta1", "eta2", "eta3"]}
    timeslot = 9

    updated_state = EntropyPool.posterior_entropy_pool(header, timeslot, initial_state)

    assert updated_state.current != initial_state.current
    # Blake2b hash output size
    assert byte_size(updated_state.current) == 32

    # Calculate expected entropy
    expected_entropy =
      Hash.blake2b_256(initial_state.current <> Util.Crypto.entropy_vrf(header.vrf_signature))

    # Assert that the current entropy matches the expected value
    assert updated_state.current == expected_entropy
  end

  test "rotates entropy history on new epoch" do
    header = %Header{vrf_signature: "sample_vrf_signature", timeslot: 600}
    initial_state = %EntropyPool{current: "initial_entropy", history: ["eta1", "eta2", "eta3"]}
    timeslot = 599

    updated_state = EntropyPool.posterior_entropy_pool(header, timeslot, initial_state)

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

    updated_state = EntropyPool.posterior_entropy_pool(header, timeslot, initial_state)

    assert updated_state.history == initial_state.history
  end
end
