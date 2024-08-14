defmodule Constants do
  @moduledoc """
  A module to hold constants used throughout the system.
  see Appendix I.3 of the GP for more information.
  """

  @doc """
  V
  The total number of validators.
  """
  @validator_count 1023
  def validator_count, do: @validator_count

  @doc """
  E
  The length of an epoch in timeslots.
  """
  @epoch_length 600
  def epoch_length, do: @epoch_length

  @doc """
  Y
  The number of slots into an epoch at which ticket-submission ends.
  """
  @ticket_submission_end 500
  def ticket_submission_end, do: @ticket_submission_end
end
