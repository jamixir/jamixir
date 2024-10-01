defmodule Constants do
  use Mockable

  @moduledoc """
  A module to hold constants used throughout the system.
  see Appendix I.3 of the GP for more information.
  """

  @doc "BS = The basic minimum balance which all services require."
  def service_minimum_balance, do: 100

  @doc "BI = The additional minimum balance required per item of elective service state."
  def additional_minimum_balance_per_item, do: 10

  @doc "BL = The additional minimum balance required per octet of elective service state."
  def additional_minimum_balance_per_octet, do: 1

  @doc "V - The total number of validators."

  defmockable(:validator_count, do: 1023)

  @doc "E - The length of an epoch in timeslots."
  defmockable(:epoch_length, do: 600)

  @doc "Y - The number of slots into an epoch at which ticket-submission ends."
  defmockable(:ticket_submission_end, do: 500)

  @doc "C - total number of cores"
  defmockable(:core_count, do: 341)

  @doc "O - The maximum number of items in the authorizations pool."
  def max_authorizations_items, do: 8

  @doc "Q - The maximum number of items in the authorization queue."
  def max_authorization_queue_items, do: 80

  @doc "WC - The basic size of our erasure-coded pieces."
  def erasure_coded_piece_size, do: 684
  @doc "WS - The size of an exported segment in erasure-coded pieces"
  def erasure_coded_exported_segment_size, do: 6

  # 4104
  def wswc, do: erasure_coded_piece_size() * erasure_coded_exported_segment_size()

  @doc "WR - The maximum size of an encoded work-report in octets."
  def max_work_report_size, do: 96 * 2 ** 10
  @doc "R - The rotation period of validator-core assignments, in timeslots."
  defmockable(:rotation_period, do: 10)
  @doc "P - The slot period, in seconds."
  def slot_period, do: 6
  @doc "K - The maximum number of tickets which may be submitted in a single extrinsic."
  def max_tickets, do: 16

  @doc "U - The period in timeslots after which reported but unavailable work may be replaced."
  def unavailability_period, do: 5

  @doc "GA - The total gas allocated to a core for Accumulation."
  defmockable(:gas_accumulation, do: 1000)

  @doc "GI : The gas allocated to invoke a work-package’s Is-Authorized logic."
  defmockable(:gas_is_authorized, do: 1000)

  @doc "GR: The total gas allocated for a work-package’s Refine logic."
  defmockable(:gas_refine, do: 1000)
end
