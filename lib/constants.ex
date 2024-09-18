defmodule Constants do
  @moduledoc """
  A module to hold constants used throughout the system.
  see Appendix I.3 of the GP for more information.
  """

  @doc """
  BS = The basic minimum balance which all services require.
  """
  def service_minimum_balance, do: 100

  @doc """
  BI = The additional minimum balance required per item of elective service state.
  """
  def additional_minimum_balance_per_item, do: 10

  @doc """
  BL = The additional minimum balance required per octet of elective service state.
  """
  def additional_minimum_balance_per_octet, do: 1

  @doc """
  V
  The total number of validators.
  """
  def validator_count, do: 1023

  @doc """
  E
  The length of an epoch in timeslots.
  """
  def epoch_length, do: 600

  @doc """
  Y
  The number of slots into an epoch at which ticket-submission ends.
  """
  def ticket_submission_end, do: 500

  @doc """
  C
  number of cores
  """
  def core_count, do: 341

  @doc """
  O
  The maximum number of items in the authorizations pool.
  """
  def max_authorizations_items, do: 8

  @doc """
  Q
  The maximum number of items in the authorization queue.
  """
  def max_authorization_queue_items, do: 80

  def erasure_coded_piece_size, do: 684
  def erasure_coded_exported_segment_size, do: 6

  # 4104
  def wswc, do: erasure_coded_piece_size() * erasure_coded_exported_segment_size()

  # WR - The maximum size of an encoded work-report in octets.
  def max_work_report_size, do: 96 * 2 ** 10
  def rotation_period, do: 10

  def slot_period, do: 6
end
