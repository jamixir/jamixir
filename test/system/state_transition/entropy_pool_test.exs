defmodule System.StateTransition.EntropyPoolTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias System.State.EntropyPool
  alias Block.{Header}
  alias Util.Hash
  import Mox

  setup_all do
    %{state: state, key_pairs: key_pairs} = build(:genesis_state_with_safrole)

    {:ok, %{state: state, key_pairs: key_pairs}}
  end

  test "updates entropy with new VRF output" do
    initial_state = %EntropyPool{n0: "initial_entropy", n1: "eta1", n2: "eta2", n3: "eta3"}

    updated_state = EntropyPool.update_current_history("vrf_output", initial_state)

    assert updated_state.n0 == Hash.blake2b_256("initial_entropy" <> "vrf_output")
    assert updated_state.n1 == initial_state.n1
    assert updated_state.n2 == initial_state.n2
    assert updated_state.n3 == initial_state.n3
  end

  test "rotates entropy history on new epoch" do
    header = %Header{vrf_signature: "sample_vrf_signature", timeslot: 600}
    initial_state = %EntropyPool{n0: "initial_entropy", n1: "eta1", n2: "eta2", n3: "eta3"}
    timeslot = 599

    updated_state = EntropyPool.rotate_history(header, timeslot, initial_state)

    # Check that the history has been updated correctly
    assert updated_state.n1 == initial_state.n0
    assert updated_state.n2 == "eta1"
    assert updated_state.n3 == "eta2"
  end

  test "does not rotate entropy history within same epoch" do
    header = %Header{vrf_signature: "sample_vrf_signature", timeslot: 602}
    initial_state = %EntropyPool{n0: "initial_entropy", n1: "eta1", n2: "eta2", n3: "eta3"}
    timeslot = 601

    updated_state = EntropyPool.rotate_history(header, timeslot, initial_state)

    assert updated_state.n1 == initial_state.n1
    assert updated_state.n2 == initial_state.n2
    assert updated_state.n3 == initial_state.n3
  end

  describe "encode/1" do
    test "entropy pool encoding smoke test" do
      assert Codec.Encoder.encode(%EntropyPool{n0: 1, n1: 2, n2: 3, n3: 4}) == <<1, 2, 3, 4>>
    end
  end

  describe "randmoness accumaltor" do
    setup do
      MockJudgements
      |> stub(:valid_header_markers?, fn _, _, _ -> true end)

      Application.put_env(:jamixir, :judgements_module, MockJudgements)

      on_exit(fn ->
        Application.delete_env(:jamixir, :judgements_module)
      end)

      :ok
    end

    test "correct entropy accumelations", %{state: state, key_pairs: key_pairs} do
      block = build(:safrole_block, state: state, key_pairs: key_pairs)

      expected_slot_sealer =
        Enum.at(state.safrole.current_epoch_slot_sealers, block.header.timeslot)

      {secret, _} = Enum.at(key_pairs, block.header.block_author_key_index)

      seal_context =
        SigningContexts.jam_ticket_seal() <>
          state.entropy_pool.n3 <> <<expected_slot_sealer.entry_index::8>>

      vrf_output =
        RingVrf.ietf_vrf_output(
          secret,
          SigningContexts.jam_entropy() <> RingVrf.ietf_vrf_output(secret, seal_context)
        )

      {:ok, new_state} = System.State.add_block(state, block)

      assert new_state.entropy_pool.n0 ==
               Util.Hash.blake2b_256(state.entropy_pool.n0 <> vrf_output)
    end
  end
end
