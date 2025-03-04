defmodule Block.Extrinsic.Disputes.Error do
  # Ordering and uniqueness errors
  def unsorted_judgements, do: :unsorted_judgements
  def unsorted_culprits, do: :unsorted_culprits
  def unsorted_verdicts, do: :unsorted_verdicts
  def unsorted_faults, do: :unsorted_faults

  # Validation errors
  def already_judged, do: :already_judged
  def bad_judgement_age, do: :bad_judgement_age
  def invalid_signature, do: :invalid_signature
  def bad_vote_split, do: :bad_vote_split
  def fault_verdict_wrong, do: :fault_verdict_wrong
  def offender_already_reported, do: :offender_already_reported

  # Set validation errors
  def not_enough_culprits, do: :not_enough_culprits
  def not_enough_faults, do: :not_enough_faults
  def invalid_header_markers, do: :invalid_header_markers
  def culprit_verdict_not_bad, do: :culprits_verdict_not_bad
end
