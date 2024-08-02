defmodule Disputes.ValidatorTest do
  use ExUnit.Case
  alias Disputes.{Verdict, Judgement, Culprit, Fault}
  alias Disputes.Validator, as: DisputesValidator
  alias Types
  alias System.State.{Validator, Judgements}
  alias Block.Header

  setup do
    # Define some sample data
    valid_key_private =
      <<0x935D5AEF2E41122B21A6590B079352130CAEE5EA80B3D9E3B8D7C2E884D64B58::256>>

    {valid_key_public, _privKeyOut} = :crypto.generate_key(:eddsa, :ed25519, valid_key_private)
    work_report_hash = <<0xAAC4C749F1D5EC07BF0502C8072E95033D48E31B1B9DFDCB8D42BD80445F713E::256>>

    # Sign the work_report_hash with the valid_key
    valid_signature = :crypto.sign(:eddsa, :none, work_report_hash, [valid_key_private, :ed25519])
    invalid_signature = <<1::512>>

    valid_judgement = %Judgement{
      validator_index: 0,
      decision: true,
      signature: valid_signature
    }

    invalid_judgement = %Judgement{
      validator_index: 1,
      decision: false,
      signature: invalid_signature
    }

    valid_verdict = %Verdict{
      work_report_hash: work_report_hash,
      epoch_index: 1,
      judgements: [valid_judgement]
    }

    invalid_verdict_judgements = %Verdict{
      work_report_hash: work_report_hash,
      epoch_index: 1,
      judgements: [invalid_judgement]
    }

    # Create another private/public key pair for a validator in the previous epoch
    prev_key_private = <<0x123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0::256>>
    {prev_key_public, _} = :crypto.generate_key(:eddsa, :ed25519, prev_key_private)

    prev_work_report_hash =
      <<0xBBC4C749F1D5EC07BF0502C8072E95033D48E31B1B9DFDCB8D42BD80445F713E::256>>

    prev_signature =
      :crypto.sign(:eddsa, :none, prev_work_report_hash, [prev_key_private, :ed25519])

    prev_judgement = %Judgement{
      validator_index: 0,
      decision: true,
      signature: prev_signature
    }

    prev_verdict = %Verdict{
      work_report_hash: prev_work_report_hash,
      epoch_index: 0,
      judgements: [prev_judgement]
    }

    prev_validator = %Validator{
      bandersnatch: <<0::256>>,
      ed25519: prev_key_public,
      bls: <<0::1152>>,
      metadata: <<0::1024>>
    }

    current_validator = %Validator{
      bandersnatch: <<0::256>>,
      ed25519: valid_key_public,
      bls: <<0::1152>>,
      metadata: <<0::1024>>
    }

    state = %System.State{
      curr_validators: [current_validator],
      prev_validators: [prev_validator],
      judgements: %Judgements{}
    }

    timeslot = 601

    {:ok,
     valid_verdict: valid_verdict,
     invalid_verdict_judgements: invalid_verdict_judgements,
     prev_verdict: prev_verdict,
     state: state,
     timeslot: timeslot}
  end

  describe "filter_valid_verdicts" do
    test "multiple valid judgements", %{
      valid_verdict: valid_verdict,
      state: state,
      timeslot: timeslot
    } do
      second_valid_judgement = %Judgement{
        validator_index: 1,
        decision: true,
        signature: valid_verdict.judgements |> hd() |> Map.get(:signature)
      }

      valid_verdict_with_multiple_judgements = %{
        valid_verdict
        | judgements: [valid_verdict.judgements |> hd(), second_valid_judgement]
      }

      assert DisputesValidator.filter_valid_verdicts(
               [valid_verdict_with_multiple_judgements],
               state,
               timeslot
             ) == [valid_verdict_with_multiple_judgements]
    end

    test "one invalid judgement and valid overall verdict", %{
      valid_verdict: valid_verdict,
      invalid_verdict_judgements: invalid_verdict_judgements,
      state: state,
      timeslot: timeslot
    } do
      valid_verdict_with_invalid_judgement = %{
        valid_verdict
        | judgements: [
            valid_verdict.judgements |> hd(),
            invalid_verdict_judgements.judgements |> hd()
          ]
      }

      assert DisputesValidator.filter_valid_verdicts(
               [valid_verdict_with_invalid_judgement],
               state,
               timeslot
             ) == [valid_verdict_with_invalid_judgement]
    end

    test "a mix of valid and invalid verdicts", %{
      valid_verdict: valid_verdict,
      invalid_verdict_judgements: invalid_verdict_judgements,
      state: state,
      timeslot: timeslot
    } do
      verdicts = [valid_verdict, invalid_verdict_judgements]
      assert DisputesValidator.filter_valid_verdicts(verdicts, state, timeslot) == [valid_verdict]
    end

    test "empty list of verdicts", %{state: state, timeslot: timeslot} do
      assert DisputesValidator.filter_valid_verdicts([], state, timeslot) == []
    end
  end

  describe "filter_valid_culprits" do
    setup do
      # First key pair
      culprit_key_private1 =
        <<0x4455AAEF2E41122B21A6590B079352130CAEE5EA80B3D9E3B8D7C2E884D64B58::256>>

      {culprit_key_public1, _} = :crypto.generate_key(:eddsa, :ed25519, culprit_key_private1)

      # Second key pair
      culprit_key_private2 =
        <<0x5566BBEF2E41122B21A6590B079352130CAEE5EA80B3D9E3B8D7C2E884D64B58::256>>

      {culprit_key_public2, _} = :crypto.generate_key(:eddsa, :ed25519, culprit_key_private2)

      valid_report_hash =
        <<0xAAC4C749F1D5EC07BF0502C8072E95033D48E31B1B9DFDCB8D42BD80445F713E::256>>

      other_report_hash =
        <<0xDEAD4C749F1D5EC07BF0502C8072E95033D48E31B1B9DFDCB8D42BD80445F713E::256>>

      valid_signature1 =
        :crypto.sign(:eddsa, :none, valid_report_hash, [culprit_key_private1, :ed25519])

      valid_signature2 =
        :crypto.sign(:eddsa, :none, valid_report_hash, [culprit_key_private2, :ed25519])

      valid_culprit = %Culprit{
        work_report_hash: valid_report_hash,
        validator_key: culprit_key_public2,
        signature: valid_signature2
      }

      culprit_in_punish_set = %Culprit{
        work_report_hash: valid_report_hash,
        validator_key: culprit_key_public1,
        signature: valid_signature1
      }

      {:ok,
       valid_culprit: valid_culprit,
       other_report_hash: other_report_hash,
       culprit_in_punish_set: culprit_in_punish_set,
       verdicts: [{valid_report_hash, 0}],
       state: %{judgements: %Judgements{punish: MapSet.new([culprit_key_public1])}}}
    end

    test "valid culprit passes", %{
      valid_culprit: valid_culprit,
      verdicts: verdicts,
      state: state
    } do
      assert DisputesValidator.filter_valid_culprits([valid_culprit], verdicts, state) == [
               valid_culprit
             ]
    end

    test "invalid signature", %{
      valid_culprit: valid_culprit,
      verdicts: verdicts,
      state: state
    } do
      bad_signature_culprit = %Culprit{
        valid_culprit
        | signature: <<1::512>>
      }

      assert DisputesValidator.filter_valid_culprits([bad_signature_culprit], verdicts, state) ==
               []
    end

    test "signature on another work report", %{
      valid_culprit: valid_culprit,
      verdicts: verdicts,
      state: state,
      other_report_hash: other_hash
    } do
      signature = :crypto.sign(:eddsa, :none, other_hash, [valid_culprit.validator_key, :ed25519])

      culprit = %Culprit{
        valid_culprit
        | signature: signature
      }

      assert DisputesValidator.filter_valid_culprits([culprit], verdicts, state) == []
    end

    test "offense with a work report that isn't in verdicts", %{
      valid_culprit: valid_culprit,
      verdicts: verdicts,
      state: state
    } do
      # Ensure the valid_culprit's work report hash is not in the verdict list
      verdicts_without_hash =
        verdicts |> Enum.filter(fn {hash, _} -> hash != valid_culprit.work_report_hash end)

      assert DisputesValidator.filter_valid_culprits(
               [valid_culprit],
               verdicts_without_hash,
               state
             ) == []
    end

    test "culprit in the punish set", %{
      culprit_in_punish_set: culprit_in_punish_set,
      verdicts: verdicts,
      state: state
    } do
      assert DisputesValidator.filter_valid_culprits(
               [culprit_in_punish_set],
               verdicts,
               state
             ) == []
    end

    test "filter_valid_culprits with empty list of culprits", %{
      verdicts: verdicts,
      state: state
    } do
      assert DisputesValidator.filter_valid_culprits([], verdicts, state) == []
    end
  end

  describe "filter_valid_faults" do
    setup do
      fault_key_private1 =
        <<0x4455AAEF2E41122B21A6590B079352130CAEE5EA80B3D9E3B8D7C2E884D64B58::256>>

      {fault_key_public1, _} = :crypto.generate_key(:eddsa, :ed25519, fault_key_private1)

      fault_key_private2 =
        <<0x5566BBEF2E41122B21A6590B079352130CAEE5EA80B3D9E3B8D7C2E884D64B58::256>>

      {fault_key_public2, _} = :crypto.generate_key(:eddsa, :ed25519, fault_key_private2)

      valid_report_hash =
        <<0xAAC4C749F1D5EC07BF0502C8072E95033D48E31B1B9DFDCB8D42BD80445F713E::256>>

      other_report_hash =
        <<0xDEAD4C749F1D5EC07BF0502C8072E95033D48E31B1B9DFDCB8D42BD80445F713E::256>>

      valid_signature1 =
        :crypto.sign(:eddsa, :none, valid_report_hash, [fault_key_private1, :ed25519])

      valid_signature2 =
        :crypto.sign(:eddsa, :none, valid_report_hash, [fault_key_private2, :ed25519])

      valid_fault = %Fault{
        work_report_hash: valid_report_hash,
        validator_key: fault_key_public2,
        signature: valid_signature2
      }

      fault_in_punish_set = %Fault{
        work_report_hash: valid_report_hash,
        validator_key: fault_key_public1,
        signature: valid_signature1
      }

      {:ok,
       valid_fault: valid_fault,
       fault_in_punish_set: fault_in_punish_set,
       other_report_hash: other_report_hash,
       verdicts: [{valid_report_hash, 0}],
       state: %{judgements: %Judgements{punish: MapSet.new([fault_key_public1])}}}
    end

    test "valid fault passes", %{
      valid_fault: valid_fault,
      verdicts: verdicts,
      state: state
    } do
      assert DisputesValidator.filter_valid_faults([valid_fault], verdicts, state) == [
               valid_fault
             ]
    end

    test "invalid signature", %{
      valid_fault: valid_fault,
      verdicts: verdicts,
      state: state
    } do
      bad_signature_fault = %Fault{
        valid_fault
        | signature: <<1::512>>
      }

      assert DisputesValidator.filter_valid_faults([bad_signature_fault], verdicts, state) ==
               []
    end

    test "signature on another work report", %{
      valid_fault: valid_fault,
      verdicts: verdicts,
      state: state,
      other_report_hash: other_hash
    } do
      signature = :crypto.sign(:eddsa, :none, other_hash, [valid_fault.validator_key, :ed25519])

      fault = %Fault{
        valid_fault
        | signature: signature
      }

      assert DisputesValidator.filter_valid_faults([fault], verdicts, state) == []
    end

    test "fault with a work report that isn't in verdicts", %{
      valid_fault: valid_fault,
      verdicts: verdicts,
      state: state
    } do
      # Ensure the valid_fault's work report hash is not in the verdict list
      verdicts_without_hash =
        verdicts |> Enum.filter(fn {hash, _} -> hash != valid_fault.work_report_hash end)

      assert DisputesValidator.filter_valid_faults(
               [valid_fault],
               verdicts_without_hash,
               state
             ) == []
    end

    test "fault in the punish set", %{
      fault_in_punish_set: fault_in_punish_set,
      verdicts: verdicts,
      state: state
    } do
      assert DisputesValidator.filter_valid_faults(
               [fault_in_punish_set],
               verdicts,
               state
             ) == []
    end

    test "filter_valid_faults with empty list of faults", %{
      verdicts: verdicts,
      state: state
    } do
      assert DisputesValidator.filter_valid_faults([], verdicts, state) == []
    end
  end


  # describe "filter_all_components" do
  #   setup do


  #     # Second key pair for culprit
  #     culprit_key_private2 =
  #       <<0x5566BBEF2E41122B21A6590B079352130CAEE5EA80B3D9E3B8D7C2E884D64B58::256>>

  #     {culprit_key_public2, _} = :crypto.generate_key(:eddsa, :ed25519, culprit_key_private2)

  #     valid_report_hash =
  #       <<0xAAC4C749F1D5EC07BF0502C8072E95033D48E31B1B9DFDCB8D42BD80445F713E::256>>

  #     other_report_hash =
  #       <<0xDEAD4C749F1D5EC07BF0502C8072E95033D48E31B1B9DFDCB8D42BD80445F713E::256>>


  #     valid_signature2 =
  #       :crypto.sign(:eddsa, :none, valid_report_hash, [culprit_key_private2, :ed25519])

  #     valid_culprit = %Culprit{
  #       work_report_hash: valid_report_hash,
  #       validator_key: culprit_key_public2,
  #       signature: valid_signature2
  #     }





  #     fault_key_private2 =
  #       <<0x5566BBEF2E41122B21A6590B079352130CAEE5EA80B3D9E3B8D7C2E884D64B58::256>>

  #     {fault_key_public2, _} = :crypto.generate_key(:eddsa, :ed25519, fault_key_private2)

  #     valid_fault = %Fault{
  #       work_report_hash: valid_report_hash,
  #       validator_key: fault_key_public2,
  #       signature: valid_signature2
  #     }


  #     {:ok,
  #      valid_culprit: valid_culprit,
  #      other_report_hash: other_report_hash,
  #      valid_fault: valid_fault,
  #      valid_report_hash: valid_report_hash,
  #      verdicts: [{valid_report_hash, 0}]}
  #   end

  #   test "filter all components", %{
  #     valid_verdict: valid_verdict,
  #     invalid_verdict_judgements: invalid_verdict_judgements,
  #     state: state,
  #     timeslot: timeslot,
  #     valid_culprit: valid_culprit,
  #     valid_fault: valid_fault,
  #     verdicts: verdicts
  #   } do
  #     disputes = %Disputes{
  #       verdicts: [valid_verdict, invalid_verdict_judgements],
  #       culprits: [valid_culprit],
  #       faults: [valid_fault]
  #     }

  #     header = %Header{timeslot: timeslot}

  #     {valid_verdicts, valid_culprits, valid_faults} =
  #       DisputesValidator.filter_all_components(disputes, state, header)

  #     assert valid_verdicts == [valid_verdict]
  #     assert valid_culprits == [valid_culprit]
  #     assert valid_faults == [valid_fault]
  #   end
  # end

end
