defmodule Block.Extrinsic.Disputes.HelperTest do
  use ExUnit.Case
  alias Block.Extrinsic.Disputes.{Verdict, Judgement, Helper, ProcessedVerdict}
  alias Types
  alias System.State.{Validator, Judgements}

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

    {:ok,
     work_report_hash: work_report_hash,
     valid_judgement: valid_judgement,
     judgement_with_invalid_signature: judgement_with_invalid_signature,
     judgement_with_non_validator_key: judgement_with_non_validator_key,
     judgement_with_invalid_index: judgement_with_invalid_index,
     prev_judgement: %Judgement{validator_index: 0, decision: true, signature: prev_signature},
     state: state,
     timeslot: timeslot}
  end

  describe "process_verdicts/3" do
    test "sanity check: processes a valid verdict", %{
      valid_judgement: valid_judgement,
      state: state,
      timeslot: timeslot,
      work_report_hash: work_report_hash
    } do
      verdict = Verdict.new(work_report_hash, 1, [valid_judgement])

      processed_verdicts = Helper.process_verdicts([verdict], state, timeslot)

      assert Map.has_key?(processed_verdicts, work_report_hash)
      assert processed_verdicts[work_report_hash].judgements_count == 1
      assert processed_verdicts[work_report_hash].positive_votes == 1
      assert processed_verdicts[work_report_hash].classification == :good
    end

    test "sanity check: processes valid verdicts with correct values", %{
      work_report_hash: work_report_hash,
      valid_judgement: valid_judgement,
      state: state,
      timeslot: timeslot
    } do
      verdcit = Verdict.new(work_report_hash, 1, [valid_judgement])

      processed_verdicts = Helper.process_verdicts([verdcit], state, timeslot)

      assert processed_verdicts[verdcit.work_report_hash] == %ProcessedVerdict{
               work_report_hash: verdcit.work_report_hash,
               validator_set_id: :current,
               judgements_count: 1,
               validator_set_size: 1,
               positive_votes: 1,
               classification: :good
             }
    end

    test "invalid epoch index filters out verdict", %{
      valid_judgement: valid_judgement,
      state: state,
      timeslot: timeslot,
      work_report_hash: work_report_hash
    } do
      verdict = Verdict.new(work_report_hash, 3, [valid_judgement])

      processed_verdicts = Helper.process_verdicts([verdict], state, timeslot)

      assert processed_verdicts == %{}
    end

    test "verdict gets filtered out due to invalid judgements", %{
      judgement_with_invalid_signature: judgement_with_invalid_signature,
      state: state,
      timeslot: timeslot,
      work_report_hash: work_report_hash
    } do
      verdict = Verdict.new(work_report_hash, 1, [judgement_with_invalid_signature])

      processed_verdicts = Helper.process_verdicts([verdict], state, timeslot)

      assert processed_verdicts == %{}
    end

    test "verdict stays with enough valid judgements despite some with non-validator keys", %{
      valid_judgement: valid_judgement,
      judgement_with_non_validator_key: judgement_with_non_validator_key,
      state: state,
      timeslot: timeslot,
      work_report_hash: work_report_hash
    } do
      verdict =
        Verdict.new(work_report_hash, 1, [valid_judgement, judgement_with_non_validator_key])

      processed_verdicts = Helper.process_verdicts([verdict], state, timeslot)

      assert Map.has_key?(processed_verdicts, work_report_hash)
      assert processed_verdicts[work_report_hash].judgements_count == 1
      assert processed_verdicts[work_report_hash].positive_votes == 1
      assert processed_verdicts[work_report_hash].classification == :good
    end

    test "verdict gets filtered out due to invalid index", %{
      judgement_with_invalid_index: judgement_with_invalid_index,
      state: state,
      timeslot: timeslot,
      work_report_hash: work_report_hash
    } do
      verdict = Verdict.new(work_report_hash, 1, [judgement_with_invalid_index])

      processed_verdicts = Helper.process_verdicts([verdict], state, timeslot)

      assert processed_verdicts == %{}
    end

    test "two valid verdicts with the same hash, one stays", %{
      valid_judgement: valid_judgement,
      state: state,
      timeslot: timeslot,
      work_report_hash: work_report_hash
    } do
      verdict1 = Verdict.new(work_report_hash, 1, [valid_judgement])

      verdict2 = Verdict.new(work_report_hash, 0, [valid_judgement])

      processed_verdicts = Helper.process_verdicts([verdict1, verdict2], state, timeslot)

      assert length(Map.keys(processed_verdicts)) == 1
      assert processed_verdicts[work_report_hash].judgements_count == 1
    end

    test "two verdicts with the same hash, only the valid one stays", %{
      valid_judgement: valid_judgement,
      judgement_with_non_validator_key: judgement_with_non_validator_key,
      state: state,
      timeslot: timeslot,
      work_report_hash: work_report_hash
    } do
      valid_verdict = Verdict.new(work_report_hash, 1, [valid_judgement])

      invalid_verdict = Verdict.new(work_report_hash, 1, [judgement_with_non_validator_key])

      processed_verdicts =
        Helper.process_verdicts([valid_verdict, invalid_verdict], state, timeslot)

      assert length(Map.keys(processed_verdicts)) == 1
      assert processed_verdicts[work_report_hash].judgements_count == 1
    end

    test "verdict with valid signature but key not in validator set gets filtered out", %{
      valid_judgement: valid_judgement,
      judgement_with_non_validator_key: judgement_with_non_validator_key,
      state: state,
      timeslot: timeslot,
      work_report_hash: work_report_hash
    } do
      verdict =
        Verdict.new(work_report_hash, 1, [valid_judgement, judgement_with_non_validator_key])

      processed_verdicts = Helper.process_verdicts([verdict], state, timeslot)

      assert Map.has_key?(processed_verdicts, work_report_hash)
      assert processed_verdicts[work_report_hash].judgements_count == 1
      assert processed_verdicts[work_report_hash].positive_votes == 1
      assert processed_verdicts[work_report_hash].classification == :good
    end

    test "processes verdict with previous validator set", %{
      prev_judgement: prev_judgement,
      state: state,
      timeslot: timeslot
    } do
      verdict = Verdict.new(<<2::256>>, 0, [prev_judgement])

      processed_verdicts = Helper.process_verdicts([verdict], state, timeslot)

      assert Map.has_key?(processed_verdicts, <<2::256>>)
      assert processed_verdicts[<<2::256>>].judgements_count == 1
      assert processed_verdicts[<<2::256>>].positive_votes == 1
      assert processed_verdicts[<<2::256>>].classification == :good
    end

    test "processes wonky verdict", %{
      valid_judgement: valid_judgement,
      state: state,
      timeslot: timeslot,
      work_report_hash: work_report_hash
    } do
      validator_count = 3

      state = %System.State{
        state
        | curr_validators: Enum.map(1..validator_count, fn _ -> state.curr_validators |> hd end)
      }

      judgements =
        Enum.map(1..validator_count, fn i ->
          %Judgement{valid_judgement | validator_index: i - 1, decision: i <= 1}
        end)

      verdict = Verdict.new(work_report_hash, 1, judgements)

      processed_verdicts = Helper.process_verdicts([verdict], state, timeslot)

      assert Map.has_key?(processed_verdicts, work_report_hash)
      assert processed_verdicts[work_report_hash].judgements_count == validator_count
      assert processed_verdicts[work_report_hash].positive_votes == 1
      assert processed_verdicts[work_report_hash].classification == :wonky
    end

    test "processes bad verdict", %{
      valid_judgement: valid_judgement,
      state: state,
      timeslot: timeslot,
      work_report_hash: work_report_hash
    } do
      verdict = Verdict.new(work_report_hash, 1, [%Judgement{valid_judgement | decision: false}])

      processed_verdicts = Helper.process_verdicts([verdict], state, timeslot)

      assert Map.has_key?(processed_verdicts, work_report_hash)
      assert processed_verdicts[work_report_hash].judgements_count == 1
      assert processed_verdicts[work_report_hash].positive_votes == 0
      assert processed_verdicts[work_report_hash].classification == :bad
    end

    test "filters out verdicts with non-classified vote count", %{
      valid_judgement: valid_judgement,
      state: state,
      timeslot: timeslot
    } do
      validator_count = 4

      state = %System.State{
        state
        | curr_validators: Enum.map(1..validator_count, fn _ -> state.curr_validators |> hd end)
      }

      judgements =
        Enum.map(1..validator_count, fn i ->
          %Judgement{valid_judgement | validator_index: i - 1, decision: i <= 2}
        end)

      verdict = Verdict.new(<<5::256>>, 1, judgements)

      processed_verdicts = Helper.process_verdicts([verdict], state, timeslot)

      refute Map.has_key?(processed_verdicts, <<5::256>>)
    end
  end
end
