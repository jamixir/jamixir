defmodule Block.Extrinsic.Disputes.Helper do
  alias Block.Extrinsic.Disputes.{Verdict, ProcessedVerdict, Judgement}
  alias System.State
  alias System.State.Validator
  alias Types
  alias Util.{Time, Crypto}

  @doc """
  Processes verdicts to generate auxiliary data, scores, and classifications.
  """
  @spec process_verdicts(list(Verdict.t()), State.t(), integer()) :: %{
          Types.hash() => ProcessedVerdict.t()
        }
  def process_verdicts(verdicts, state, timeslot) do
    verdicts
    # Filter out verdicts that are not from the current or previous epoch
    |> Enum.filter(&valid_epoch_index?(&1, timeslot))
    # Filter out judgements that are not valid and build auxiliary data
    |> Enum.map(&filter_and_build_verdict_data(&1, state, timeslot))
    # Filter out verdicts with incorrect judgement count
    |> Enum.filter(&valid_judgement_count?/1)
    # Sort by work report hash
    |> Enum.sort_by(& &1.work_report_hash)
    # Ensure uniqueness by work report hash
    |> Enum.uniq_by(& &1.work_report_hash)
    # Convert to map for easy lookup
    |> Enum.into(%{}, fn verdict -> {verdict.work_report_hash, verdict} end)
  end

  defp filter_and_build_verdict_data(verdict, state, timeslot) do
    # Determine the validator set to use for this verdict
    {validator_set_id, validator_set} = validator_set(verdict, state, timeslot)
    # Filter out invalid judgements
    valid_judgements = filter_valid_judgements(verdict, validator_set)
    judgements_count = length(valid_judgements)
    positive_votes = Enum.count(valid_judgements, & &1.decision)
    classification = classify_verdict(positive_votes, length(validator_set))

    %ProcessedVerdict{
      work_report_hash: verdict.work_report_hash,
      validator_set_id: validator_set_id,
      judgements_count: judgements_count,
      validator_set_size: length(validator_set),
      positive_votes: positive_votes,
      classification: classification
    }
  end

  defp filter_valid_judgements(%Verdict{work_report_hash: wrh, judgements: jms}, validator_set) do
    # Filter out jusgment that theier singature does not match the validator public key at the given index
    Enum.filter(jms, fn judgement ->
      verify_judgement_signature?(judgement, wrh, validator_set)
    end)
    # Ensure uniqueness by validator index
    |> Enum.sort_by(& &1.validator_index)
    |> Enum.uniq_by(& &1.validator_index)
  end

  # Determines if a signature in a judgement is valid for the given work report hash.
  @spec verify_judgement_signature?(Judgement.t(), Types.hash(), list(Validator.t())) :: boolean()
  defp verify_judgement_signature?(
         %Judgement{signature: signature, validator_index: index},
         work_report_hash,
         validators
       ) do
    case Enum.at(validators, index) do
      %Validator{ed25519: public_key} ->
        Crypto.verify_signature(signature, work_report_hash, public_key)

      _ ->
        false
    end
  end

  defp valid_judgement_count?(%ProcessedVerdict{
         validator_set_size: size,
         judgements_count: judgements_count
       }) do
    judgements_count == div(2 * size, 3) + 1
  end

  defp classify_verdict(positive_votes, validator_count) do
    good_threshold = div(2 * validator_count, 3) + 1
    wonky_threshold = div(validator_count, 3)

    cond do
      positive_votes == good_threshold -> :good
      positive_votes == 0 -> :bad
      positive_votes == wonky_threshold -> :wonky
      true -> :undefined
    end
  end

  defp valid_epoch_index?(%Verdict{epoch_index: epoch_index}, timeslot) do
    current_epoch_index = Time.epoch_index(timeslot)
    (current_epoch_index - epoch_index) in [0, 1]
  end

  defp validator_set(
         %Verdict{epoch_index: epoch_index},
         %State{curr_validators: curr_validators, prev_validators: prev_validators},
         timeslot
       ) do
    current_epoch_index = Time.epoch_index(timeslot)

    case current_epoch_index - epoch_index do
      0 -> {:current, curr_validators}
      1 -> {:previous, prev_validators}
    end
  end
end
