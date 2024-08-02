defmodule Disputes.Helper do
  alias Disputes.{Verdict, Verifier}
  alias System.State
  alias System.State.{Validator}
  alias Types
  alias Util.Time

  @doc """
  Creates a list of verdicts with the number of positive votes.
  """
  @spec create_verdicts_scores(list(Verdict.t())) :: list({Types.hash(), integer()})
  def create_verdicts_scores(valid_verdicts) do
    valid_verdicts
    |> Enum.map(fn %Verdict{work_report_hash: report_hash, judgements: judgements} ->
      positive_votes = Enum.count(judgements, & &1.decision)
      {report_hash, positive_votes}
    end)
  end

  @doc """
  Classifies verdicts based on the number of positive votes.
  """
  @spec classify_verdicts(list({Types.hash(), integer()}), integer()) ::
          list({Types.hash(), atom()})
  def classify_verdicts(verdict_scores, validator_count) do
    good_threshold = div(2 * validator_count, 3) + 1
    wonky_threshold = div(validator_count, 3)

    Enum.map(verdict_scores, fn {report_hash, positive_votes} ->
      classification =
        cond do
          positive_votes == good_threshold -> :good
          positive_votes == 0 -> :bad
          positive_votes == wonky_threshold -> :wonky
          true -> :undefined
        end

      {report_hash, classification}
    end)
  end

  @doc """
  Determines if a verdict is valid based on the epoch index and number of valid judgements.
  """

  def valid_verdict?(verdict, state, timeslot) do
    valid_epoch_index?(verdict, timeslot) and enough_valid_judgements?(verdict, state, timeslot)
  end

  @doc """
  Eq. (100) and (101) in the paper.
  Validates whether an offense (culprit or fault) is valid based on
  a. report_hash being in the bad set or in the verdict bad set
  b. validator_key not being in the punish set
  """
  @spec valid_offense?(map(), list({Types.hash(), integer()}), State.t()) :: boolean()
  def valid_offense?(
        %{work_report_hash: report_hash, validator_key: key},
        verdicts,
        state
      ) do
    verdict_badset =
      Enum.filter(verdicts, fn {_hash, votes} -> votes == 0 end)
      |> Enum.map(fn {hash, _votes} -> hash end)

    report_hash in state.judgements.bad or
      (report_hash in verdict_badset and
         not MapSet.member?(state.judgements.punish, key))
  end

  # Determines the appropriate validator set for the given epoch index.
  @spec validator_set(Verdict.t(), State.t(), integer()) :: list(Validator.t())
  defp validator_set(
         %Verdict{epoch_index: epoch_index},
         %State{curr_validators: curr_validators, prev_validators: prev_validators},
         timeslot
       ) do
    current_epoch_index = Time.epoch_index(timeslot)

    case current_epoch_index - epoch_index do
      0 -> curr_validators
      1 -> prev_validators
    end
  end

  # Private functions below.

  # Checks if the epoch index is valid for the given verdict.

  defp valid_epoch_index?(%Verdict{epoch_index: epoch_index}, timeslot) do
    current_epoch_index = Time.epoch_index(timeslot)
    (current_epoch_index - epoch_index) in [0, 1]
  end

  # Checks if there are enough valid judgements in a verdict.

  defp enough_valid_judgements?(
         %Verdict{judgements: judgements, work_report_hash: message} = verdict,
         state,
         timeslot
       ) do
    validator_set = validator_set(verdict, state, timeslot)

    valid_judgments =
      Enum.filter(judgements, fn judgement ->
        Verifier.verify_judgement_signature?(judgement, message, validator_set)
      end)

    length(valid_judgments) >= required_judgement_count(validator_set)
  end

  # Calculates the required number of valid judgements.

  @spec required_judgement_count(list(Validator.t())) :: integer()
  defp required_judgement_count(validators) do
    div(length(validators) * 2, 3) + 1
  end
end
