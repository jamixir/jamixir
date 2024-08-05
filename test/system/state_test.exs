defmodule System.StateTest do
  use ExUnit.Case

  alias System.State
  alias Block.{Header, Extrinsic}
  alias Block
  alias Util.Hash
  alias Disputes.{Verdict, Culprit, Fault, Judgement}
  alias System.State.{Validator, Judgements}

  setup do
    # Setup keys and signatures
    work_report_hash = <<0xAAC4C749F1D5EC07BF0502C8072E95033D48E31B1B9DFDCB8D42BD80445F713E::256>>

    valid_key_private =
      <<0x935D5AEF2E41122B21A6590B079352130CAEE5EA80B3D9E3B8D7C2E884D64B58::256>>

    {valid_key_public, _privKeyOut} = :crypto.generate_key(:eddsa, :ed25519, valid_key_private)
    valid_signature = :crypto.sign(:eddsa, :none, work_report_hash, [valid_key_private, :ed25519])

    prev_key_private =
      <<0x123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0::256>>

    {prev_key_public, _} = :crypto.generate_key(:eddsa, :ed25519, prev_key_private)
    prev_signature = :crypto.sign(:eddsa, :none, <<2::256>>, [prev_key_private, :ed25519])

    valid_judgement = %Judgement{
      validator_index: 0,
      decision: true,
      signature: valid_signature
    }

    valid_offense = %Culprit{
      work_report_hash: work_report_hash,
      validator_key: valid_key_public,
      signature: valid_signature
    }

    state = %System.State{
      curr_validators: [%Validator{ed25519: valid_key_public}],
      prev_validators: [%Validator{ed25519: prev_key_public}],
      judgements: %Judgements{}
    }

    header = %Header{timeslot: 601}

    {:ok,
     work_report_hash: work_report_hash,
     valid_judgement: valid_judgement,
     valid_offense: valid_offense,
     state: state,
     header: header,
     valid_key_private: valid_key_private,
     valid_key_public: valid_key_public}
  end

  test "add_block/1 correctly set timeslot" do
    state = %State{
      entropy_pool: %EntropyPool{current: "initial_entropy", history: ["eta1", "eta2", "eta3"]},
      timeslot: 6
    }

    block = %Block{
      header: %Header{timeslot: 7, vrf_signature: "0x00000000000"},
      extrinsic: %Block.Extrinsic{}
    }

    assert State.add_block(state, block).timeslot === 7
  end

  describe "add_block/2" do
    test "adds to good set", %{
      state: state,
      header: header,
      work_report_hash: work_report_hash,
      valid_judgement: valid_judgement,
      valid_key_private: valid_key_private,
      valid_key_public: valid_key_public
    } do
      validator_count = 3

      state = %System.State{
        state
        | curr_validators:
            Enum.map(1..validator_count, fn _ -> %Validator{ed25519: valid_key_public} end)
      }

      positive_votes =
        Enum.map(1..validator_count, fn i ->
          %Judgement{valid_judgement | validator_index: i - 1, decision: true}
        end)

      verdict = %Verdict{
        work_report_hash: work_report_hash,
        epoch_index: 1,
        judgements: positive_votes
      }

      disputes = %Disputes{verdicts: [verdict], culprits: [], faults: []}
      block = %Block{header: header, extrinsic: %{disputes: disputes}}

      new_state = State.add_block(state, block)

      assert MapSet.member?(new_state.judgements.good, work_report_hash)
    end

    test "adds to wonky set", %{
      state: state,
      header: header,
      work_report_hash: work_report_hash,
      valid_judgement: valid_judgement,
      valid_key_private: valid_key_private,
      valid_key_public: valid_key_public
    } do
      validator_count = 3

      state = %System.State{
        state
        | curr_validators:
            Enum.map(1..validator_count, fn _ -> %Validator{ed25519: valid_key_public} end)
      }

      wonky_votes =
        Enum.map(1..validator_count, fn i ->
          %Judgement{valid_judgement | validator_index: i - 1, decision: i == 1}
        end)

      verdict = %Verdict{
        work_report_hash: work_report_hash,
        epoch_index: 1,
        judgements: wonky_votes
      }

      disputes = %Disputes{verdicts: [verdict], culprits: [], faults: []}
      block = %Block{header: header, extrinsic: %{disputes: disputes}}

      new_state = State.add_block(state, block)

      assert MapSet.member?(new_state.judgements.wonky, work_report_hash)
    end

    test "updates state with valid disputes", %{
      state: state,
      header: header,
      work_report_hash: work_report_hash,
      valid_judgement: valid_judgement,
      valid_offense: valid_offense
    } do
      verdict = %Verdict{
        work_report_hash: work_report_hash,
        epoch_index: 1,
        judgements: [%Judgement{valid_judgement | decision: false}]
      }

      disputes = %Disputes{verdicts: [verdict], culprits: [valid_offense], faults: []}
      block = %Block{header: header, extrinsic: %{disputes: disputes}}

      new_state = State.add_block(state, block)

      assert MapSet.member?(new_state.judgements.bad, work_report_hash)
      assert MapSet.member?(new_state.judgements.punish, valid_offense.validator_key)
    end

    test "filters out duplicate work report hashes", %{
      state: state,
      header: header,
      work_report_hash: work_report_hash,
      valid_judgement: valid_judgement,
      valid_offense: valid_offense
    } do
      state_judgements = %Judgements{
        good: MapSet.new(),
        bad: MapSet.new([work_report_hash]),
        wonky: MapSet.new(),
        punish: MapSet.new()
      }

      state = %{state | judgements: state_judgements}

      verdict = %Verdict{
        work_report_hash: work_report_hash,
        epoch_index: 1,
        judgements: [%Judgement{valid_judgement | decision: false}]
      }

      disputes = %Disputes{verdicts: [verdict], culprits: [valid_offense], faults: []}
      block = %Block{header: header, extrinsic: %{disputes: disputes}}

      new_state = State.add_block(state, block)

      assert MapSet.member?(new_state.judgements.bad, work_report_hash)
      assert not MapSet.member?(new_state.judgements.good, work_report_hash)
      assert not MapSet.member?(new_state.judgements.wonky, work_report_hash)
    end

    test "updates punish set with valid offenses", %{
      state: state,
      header: header,
      work_report_hash: work_report_hash,
      valid_judgement: valid_judgement,
      valid_key_private: valid_key_private,
      valid_key_public: valid_key_public
    } do
      work_report_hash_1 = <<1::256>>
      work_report_hash_2 = <<2::256>>

      valid_signature_1 =
        :crypto.sign(:eddsa, :none, work_report_hash_1, [valid_key_private, :ed25519])

      valid_signature_2 =
        :crypto.sign(:eddsa, :none, work_report_hash_2, [valid_key_private, :ed25519])

      culprit = %Culprit{
        work_report_hash: work_report_hash_1,
        validator_key: valid_key_public,
        signature: valid_signature_1
      }

      fault = %Fault{
        work_report_hash: work_report_hash_2,
        decision: false,
        validator_key: valid_key_public,
        signature: valid_signature_2
      }

      state = %System.State{
        state
        | curr_validators: [%Validator{ed25519: valid_key_public}],
          judgements: %Judgements{bad: MapSet.new([work_report_hash_1, work_report_hash_2])}
      }

      verdict = %Verdict{
        work_report_hash: work_report_hash,
        epoch_index: 1,
        judgements: [%Judgement{valid_judgement | decision: false}]
      }

      disputes = %Disputes{verdicts: [verdict], culprits: [culprit], faults: [fault]}
      block = %Block{header: header, extrinsic: %{disputes: disputes}}

      new_state = State.add_block(state, block)

      assert MapSet.member?(new_state.judgements.bad, work_report_hash)
      assert MapSet.member?(new_state.judgements.punish, valid_key_public)
    end
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
      expected_entropy =
        Hash.blake2b_256(initial_state.current <> State.entropy_vrf(header.vrf_signature))

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
