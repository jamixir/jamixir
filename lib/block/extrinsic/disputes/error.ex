defmodule Block.Extrinsic.Disputes.Error do
  # Ordering and uniqueness errors
  def unsorted_judgements, do: :unsorted_judgements
  def unsorted_culprits, do: :unsorted_culprits
  def unsorted_faults, do: :unsorted_faults
  def unsorted_verdicts, do: :unsorted_verdicts

  # Validation errors
  def already_judged, do: :already_judged
  def invalid_epoch, do: :invalid_epoch
  def invalid_signature, do: :invalid_signature
  def invalid_vote_count, do: :invalid_vote_count
  def invalid_fault_vote, do: :invalid_fault_vote
  def invalid_validator, do: :invalid_validator
  def offender_already_reported, do: :offender_already_reported

  # Set validation errors
  def not_enough_culprits, do: :not_enough_culprits
  def not_enough_faults, do: :not_enough_faults
  def invalid_header_markers, do: :invalid_header_markers
  def culprit_verdict_not_bad, do: :culprit_verdict_not_bad
end
