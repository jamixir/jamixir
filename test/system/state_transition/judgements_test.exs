defmodule System.StateTransition.JudgementsTest do
  use ExUnit.Case
  import Jamixir.Factory

  alias System.State
  alias Block.{Header, Extrinsic}
  alias Block.Extrinsic.Disputes
  alias Block.Extrinsic.Disputes.{Verdict, Culprit, Fault, Judgement}
  alias System.State.{Validator, Judgements}

  setup do
    # Setup keys and signatures
    work_report_hash = <<0xAAC4C749F1D5EC07BF0502C8072E95033D48E31B1B9DFDCB8D42BD80445F713E::256>>

    valid_key_private =
      <<0x935D5AEF2E41122B21A6590B079352130CAEE5EA80B3D9E3B8D7C2E884D64B58::256>>

    {valid_key_public, _privKeyOut} = :crypto.generate_key(:eddsa, :ed25519, valid_key_private)
    valid_signature = :crypto.sign(:eddsa, :none, work_report_hash, [valid_key_private, :ed25519])

    prev_key_private = <<0x123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0::256>>
    {prev_key_public, _} = :crypto.generate_key(:eddsa, :ed25519, prev_key_private)

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
      build(:genesis_state)
      | curr_validators: [%Validator{ed25519: valid_key_public}],
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

  test "adds to good set", %{
    state: state,
    header: header,
    work_report_hash: work_report_hash,
    valid_judgement: valid_judgement,
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
    block = %Block{header: header, extrinsic: %Extrinsic{disputes: disputes}}

    new_state = State.add_block(state, block)

    assert MapSet.member?(new_state.judgements.good, work_report_hash)
  end

  test "adds to wonky set", %{
    state: state,
    header: header,
    work_report_hash: work_report_hash,
    valid_judgement: valid_judgement,
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
    block = %Block{header: header, extrinsic: %Extrinsic{disputes: disputes}}

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
    block = %Block{header: header, extrinsic: %Extrinsic{disputes: disputes}}

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
    block = %Block{header: header, extrinsic: %Extrinsic{disputes: disputes}}

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
    block = %Block{header: header, extrinsic: %Extrinsic{disputes: disputes}}

    new_state = State.add_block(state, block)

    assert MapSet.member?(new_state.judgements.bad, work_report_hash)
    assert MapSet.member?(new_state.judgements.punish, valid_key_public)
  end

  describe "encode/1" do
    test "judgements encoding smoke test" do
      j = %Judgements{
        good: MapSet.new([<<1>>, <<2>>]),
        bad: MapSet.new([<<2>>]),
        wonky: MapSet.new([<<3>>]),
        punish: MapSet.new([<<4>>])
      }

      assert Codec.Encoder.encode(j) == <<2, 1, 2, 1, 2, 1, 3, 1, 4>>
    end
  end
end
