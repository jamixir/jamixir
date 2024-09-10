defmodule System.StateTransition.EntropyPoolTest do
  use ExUnit.Case

  alias System.State.EntropyPool
  alias Block.{Header}
  alias Util.Hash

  test "updates entropy with new VRF output" do
    header = %Header{vrf_signature: "sample_vrf_signature", timeslot: 10}
    initial_state = %EntropyPool{n0: "initial_entropy", n1: "eta1", n2: "eta2", n3: "eta3"}
    timeslot = 9

    updated_state = EntropyPool.posterior_entropy_pool(header, timeslot, initial_state)

    assert updated_state.n0 != initial_state.n0
    # Blake2b hash output size
    assert byte_size(updated_state.n0) == 32

    # Calculate expected entropy
    expected_entropy =
      Hash.blake2b_256(initial_state.n0 <> Util.Crypto.entropy_vrf(header.vrf_signature))

    # Assert that the current entropy matches the expected value
    assert updated_state.n0 == expected_entropy
  end

  test "rotates entropy history on new epoch" do
    header = %Header{vrf_signature: "sample_vrf_signature", timeslot: 600}
    initial_state = %EntropyPool{n0: "initial_entropy", n1: "eta1", n2: "eta2", n3: "eta3"}
    timeslot = 599

    updated_state = EntropyPool.posterior_entropy_pool(header, timeslot, initial_state)

    # Check that the history has been updated correctly
    assert updated_state.n1 == initial_state.n0
    assert updated_state.n2 == "eta1"
    assert updated_state.n3 == "eta2"
  end

  test "does not rotate entropy history within same epoch" do
    header = %Header{vrf_signature: "sample_vrf_signature", timeslot: 602}
    initial_state = %EntropyPool{n0: "initial_entropy", n1: "eta1", n2: "eta2", n3: "eta3"}
    timeslot = 601

    updated_state = EntropyPool.posterior_entropy_pool(header, timeslot, initial_state)

    assert updated_state.n1 == initial_state.n1
    assert updated_state.n2 == initial_state.n2
    assert updated_state.n3 == initial_state.n3
  end

  describe "encode/1" do
    test "entropy pool encoding smoke test" do
      assert Codec.Encoder.encode(%EntropyPool{n0: 1, n1: 2, n2: 3, n3: 4}) == <<1, 2, 3, 4>>
    end
  end
end
