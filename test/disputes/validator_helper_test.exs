defmodule Disputes.HelperTest do
  use ExUnit.Case
  alias Disputes.{Verdict, Judgement, Helper}
  alias Types
  alias System.State.{Validator, Judgements}

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

  describe "create_verdicts_scores/1" do
    test "correctly counts the number of positive votes" do
      judgements = [
        %Judgement{decision: true},
        %Judgement{decision: false},
        %Judgement{decision: true}
      ]

      verdicts = [%Verdict{work_report_hash: <<1::256>>, judgements: judgements}]

      expected_verdicts = [{<<1::256>>, 2}]
      assert Helper.create_verdicts_scores(verdicts) == expected_verdicts
    end
  end

  describe "valid_verdict?/3" do
    test "valid verdict in current epoch", %{
      valid_verdict: valid_verdict,
      state: state,
      timeslot: timeslot
    } do
      assert Helper.valid_verdict?(valid_verdict, state, timeslot)
    end

    test "valid verdict in previous epoch", %{
      prev_verdict: valid_verdict,
      state: state,
      timeslot: timeslot
    } do
      assert Helper.valid_verdict?(valid_verdict, state, timeslot)
    end

    test "future epoch index", %{
      valid_verdict: valid_verdict,
      state: state,
      timeslot: timeslot
    } do
      refute Helper.valid_verdict?(%{valid_verdict | epoch_index: 3}, state, timeslot)
    end

    test "incorrect_epoch_index", %{
      valid_verdict: valid_verdict,
      state: state,
      timeslot: timeslot
    } do
      refute Helper.valid_verdict?(%{valid_verdict | epoch_index: 0}, state, timeslot)
    end

    test "invalid judgements", %{
      invalid_verdict_judgements: invalid_verdict_judgements,
      state: state,
      timeslot: timeslot
    } do
      refute Helper.valid_verdict?(invalid_verdict_judgements, state, timeslot)
    end

    test "valid signature but wrong work_report_hash", %{
      valid_verdict: valid_verdict,
      state: state,
      timeslot: timeslot
    } do
      valid_verdict_with_wrong_hash = %{
        valid_verdict
        | work_report_hash: <<0x0::256>>
      }

      refute Helper.valid_verdict?(valid_verdict_with_wrong_hash, state, timeslot)
    end
  end



  describe "valid_offense?/3" do
    test "offense in state's bad set", %{
      state: state
    } do
      state_with_bad_set = %System.State{
        state
        | judgements: %Judgements{bad: MapSet.new([<<1::256>>])}
      }

      offense = %{work_report_hash: <<1::256>>, validator_key: <<1::256>>}
      assert Helper.valid_offense?(offense, [], state_with_bad_set)
    end

    test "offense has 0 positive judgments", %{
      state: state
    } do
      verdicts = [{<<1::256>>, 0}]
      offense = %{work_report_hash: <<1::256>>, validator_key: <<1::256>>}
      assert Helper.valid_offense?(offense, verdicts, state)
    end

    test "offense rejected because validator is already in the punish set", %{
      state: state
    } do
      state_with_punish_set = %System.State{
        state
        | judgements: %Judgements{punish: MapSet.new([<<1::256>>])}
      }

      offense = %{work_report_hash: <<1::256>>, validator_key: <<1::256>>}
      refute Helper.valid_offense?(offense, [], state_with_punish_set)
    end

    test "offence rejected because it's positive judgment count > 0", %{
      state: state
    } do
      verdicts = [{<<1::256>>, 2}]
      offense = %{work_report_hash: <<1::256>>, validator_key: <<1::256>>}
      refute Helper.valid_offense?(offense, verdicts, state)
    end
  end
end
