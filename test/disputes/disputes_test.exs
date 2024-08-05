defmodule Disputes.Test do
  use ExUnit.Case
  alias Disputes
  alias Disputes.{Verdict, Judgement, Helper, ProcessedVerdict, Culprit, Fault}
  alias Types
  alias System.State.{Validator, Judgements}
  alias System.State
  alias Block.Header

  setup do
    work_report_hash = <<0xAAC4C749F1D5EC07BF0502C8072E95033D48E31B1B9DFDCB8D42BD80445F713E::256>>

    valid_key_private =
      <<0x935D5AEF2E41122B21A6590B079352130CAEE5EA80B3D9E3B8D7C2E884D64B58::256>>

    {valid_key_public, _privKeyOut} = :crypto.generate_key(:eddsa, :ed25519, valid_key_private)
    valid_signature = :crypto.sign(:eddsa, :none, work_report_hash, [valid_key_private, :ed25519])

    non_validator_key_private =
      <<0x123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0::256>>

    non_validator_signature =
      :crypto.sign(:eddsa, :none, work_report_hash, [non_validator_key_private, :ed25519])

    prev_key_private = <<0x123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0::256>>
    {prev_key_public, _} = :crypto.generate_key(:eddsa, :ed25519, prev_key_private)
    prev_signature = :crypto.sign(:eddsa, :none, <<2::256>>, [prev_key_private, :ed25519])

    valid_judgement = %Judgement{
      validator_index: 0,
      decision: true,
      signature: valid_signature
    }

    judgement_with_invalid_signature = %Judgement{
      validator_index: 0,
      decision: true,
      signature: <<1::512>>
    }

    judgement_with_non_validator_key = %Judgement{
      validator_index: 0,
      decision: true,
      signature: non_validator_signature
    }

    judgement_with_invalid_index = %Judgement{
      # Assuming validator set length is 1
      validator_index: 2,
      decision: true,
      signature: valid_signature
    }

    current_validator = %Validator{
      bandersnatch: <<0::256>>,
      ed25519: valid_key_public,
      bls: <<0::1152>>,
      metadata: <<0::1024>>
    }

    previous_validator = %Validator{
      bandersnatch: <<0::256>>,
      ed25519: prev_key_public,
      bls: <<0::1152>>,
      metadata: <<0::1024>>
    }

    state = %System.State{
      curr_validators: [current_validator],
      prev_validators: [previous_validator],
      judgements: %Judgements{}
    }

    timeslot = 601

    header = %Header{timeslot: timeslot}

    culprit = %Culprit{
      work_report_hash: work_report_hash,
      validator_key: valid_key_public,
      signature: valid_signature
    }

    {:ok,
     valid_key_private: valid_key_private,
     valid_key_public: valid_key_public,
     work_report_hash: work_report_hash,
     culprit: culprit,
     valid_judgement: valid_judgement,
     judgement_with_invalid_signature: judgement_with_invalid_signature,
     judgement_with_non_validator_key: judgement_with_non_validator_key,
     judgement_with_invalid_index: judgement_with_invalid_index,
     prev_judgement: %Judgement{validator_index: 0, decision: true, signature: prev_signature},
     state: state,
     header: header}
  end

  describe "validate_and_process_disputes/3" do
    test "filters out duplicate verdicts", %{
      valid_judgement: valid_judgement,
      state: state,
      header: header,
      work_report_hash: work_report_hash
    } do
      verdict = %Verdict{
        work_report_hash: work_report_hash,
        epoch_index: 1,
        judgements: [valid_judgement]
      }

      state = %System.State{
        state
        | judgements: %Judgements{good: MapSet.new([work_report_hash])}
      }

      disputes = %Disputes{verdicts: [verdict], culprits: [], faults: []}
      {processed_verdicts, _} = Disputes.validate_and_process_disputes(disputes, state, header)

      assert processed_verdicts == %{}
    end

    test "sanity check: processes valid offenses", %{
      state: state,
      header: header,
      valid_judgement: valid_judgement,
      valid_key_private: valid_key_private,
      valid_key_public: valid_key_public
    } do
      new_key_private =
        <<0x123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0::256>>

      {new_key_public, _} = :crypto.generate_key(:eddsa, :ed25519, new_key_private)

      work_report_hash_1 = <<1::256>>
      work_report_hash_2 = <<2::256>>

      valid_signature_1 =
        :crypto.sign(:eddsa, :none, work_report_hash_1, [valid_key_private, :ed25519])

      valid_signature_2 =
        :crypto.sign(:eddsa, :none, work_report_hash_2, [new_key_private, :ed25519])

      culprit = %Culprit{
        work_report_hash: work_report_hash_1,
        validator_key: valid_key_public,
        signature: valid_signature_1
      }

      fault = %Fault{
        work_report_hash: work_report_hash_2,
        decision: false,
        validator_key: new_key_public,
        signature: valid_signature_2
      }

      state = %System.State{
        state
        | judgements: %Judgements{bad: MapSet.new([work_report_hash_2])}
      }

      verdict = %Verdict{
        work_report_hash: work_report_hash_1,
        epoch_index: 1,
        judgements: [
          %Judgement{decision: false, validator_index: 0, signature: valid_signature_1}
        ]
      }

      disputes = %Disputes{verdicts: [verdict], culprits: [culprit], faults: [fault]}

      {processed_verdicts, valid_offenses} =
        Disputes.validate_and_process_disputes(disputes, state, header)

      assert Map.has_key?(processed_verdicts, work_report_hash_1)
      assert length(valid_offenses) == 2
    end

    test "filters out offenses with validator key already in punish set", %{
      culprit: culprit,
      state: state,
      header: header,
      work_report_hash: work_report_hash,
      valid_judgement: valid_judgement
    } do
      state = %System.State{
        state
        | judgements: %Judgements{punish: MapSet.new([culprit.validator_key])}
      }

      verdict = %Verdict{
        work_report_hash: work_report_hash,
        epoch_index: 1,
        judgements: [valid_judgement]
      }

      disputes = %Disputes{verdicts: [verdict], culprits: [culprit], faults: []}

      {processed_verdicts, valid_offenses} =
        Disputes.validate_and_process_disputes(disputes, state, header)

      assert Map.has_key?(processed_verdicts, work_report_hash)
      assert valid_offenses == []
    end

    test "filters out offenses not in bad set and not classified as bad", %{
      culprit: culprit,
      state: state,
      header: header,
      work_report_hash: work_report_hash,
      valid_judgement: valid_judgement
    } do
      verdict = %Verdict{
        work_report_hash: work_report_hash,
        epoch_index: 1,
        judgements: [%Judgement{valid_judgement | decision: true}]
      }

      disputes = %Disputes{verdicts: [verdict], culprits: [culprit], faults: []}

      {processed_verdicts, valid_offenses} =
        Disputes.validate_and_process_disputes(disputes, state, header)

      assert Map.has_key?(processed_verdicts, work_report_hash)
      assert valid_offenses == []
    end

    test "valid offense in bad set and not in punish set pass", %{
      culprit: culprit,
      state: state,
      header: header,
      work_report_hash: work_report_hash,
      valid_judgement: valid_judgement
    } do
      state = %System.State{
        state
        | judgements: %Judgements{bad: MapSet.new([work_report_hash])}
      }

      verdict = %Verdict{
        work_report_hash: work_report_hash,
        epoch_index: 1,
        judgements: [valid_judgement]
      }

      disputes = %Disputes{verdicts: [verdict], culprits: [culprit], faults: []}

      {processed_verdicts, valid_offenses} =
        Disputes.validate_and_process_disputes(disputes, state, header)

      # assert Map.has_key?(processed_verdicts, work_report_hash)
      assert length(valid_offenses) == 1
    end

    test "valid offense with :bad classification and not in punish set pass", %{
      culprit: culprit,
      state: state,
      header: header,
      work_report_hash: work_report_hash,
      valid_judgement: valid_judgement
    } do
      verdict = %Verdict{
        work_report_hash: work_report_hash,
        epoch_index: 1,
        judgements: [%Judgement{valid_judgement | decision: false}]
      }

      disputes = %Disputes{verdicts: [verdict], culprits: [culprit], faults: []}

      {processed_verdicts, valid_offenses} =
        Disputes.validate_and_process_disputes(disputes, state, header)

      assert Map.has_key?(processed_verdicts, work_report_hash)
      assert length(valid_offenses) == 1
    end
  end
end
