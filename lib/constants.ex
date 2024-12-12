defmodule Constants do
  use Mockable

  @moduledoc """
  A module to hold constants used throughout the system.
  see Appendix I.3 of the GP for more information.
  """

  @spec additional_minimum_balance_per_item() :: Types.balance()
  @doc "BI = The additional minimum balance required per item of elective service state."
  def additional_minimum_balance_per_item, do: 10

  @spec additional_minimum_balance_per_octet() :: Types.balance()
  @doc "BL = The additional minimum balance required per octet of elective service state."
  def additional_minimum_balance_per_octet, do: 1

  @spec service_minimum_balance() :: Types.balance()
  @doc "BS = The basic minimum balance which all services require."
  def service_minimum_balance, do: 100

  @doc "C - total number of cores"
  defmockable(:core_count, do: Jamixir.config()[:core_count])

  @doc "E - The length of an epoch in timeslots."
  defmockable(:epoch_length, do: Jamixir.config()[:epoch_length])

  @doc "H - The size of recent history, in blocks."
  defmockable(:recent_history_size, do: 8)

  @doc "J - The maximum sum of dependency items in a work-report."
  defmockable(:max_work_report_dep_sum, do: 8)

  @doc "GA - The total gas allocated to a core for Accumulation."
  defmockable(:gas_accumulation, do: 10_000_000)

  @doc "GI : The gas allocated to invoke a work-package's Is-Authorized logic."
  defmockable(:gas_is_authorized, do: 1_000_000)

  @doc "GR: The total gas allocated for a work-package's Refine logic."
  defmockable(:gas_refine, do: 500_000_000)

  @doc "GT: The total gas allocated across all cores for Accumulation."
  defmockable(:gas_total_accumulation, do: 35_000_000)

  @doc "K - The maximum number of tickets which may be submitted in a single extrinsic."
  defmockable(:max_tickets_pre_extrinsic, do: Jamixir.config()[:max_tickets_pre_extrinsic])

  @doc "L = 14, 400: The maximum age in timeslots of the lookup anchor."
  def max_age_lookup_anchor, do: 14_400

  defmockable(:tickets_per_validator, do: Jamixir.config()[:tickets_per_validator])

  @doc "O - The maximum number of items in the authorizations pool."
  def max_authorizations_items, do: 8

  @doc "P - The timeslot period, in seconds."
  def slot_period, do: 6

  @doc "Q - The maximum number of items in the authorization queue."
  def max_authorization_queue_items, do: 80

  @doc "R - The rotation period of validator-core assignments, in timeslots."
  defmockable(:rotation_period, do: Jamixir.config()[:rotation_period])

  @doc "U - The period in timeslots after which reported but unavailable work may be replaced."
  def unavailability_period, do: 5

  @doc "V - The total number of validators."
  defmockable(:validator_count, do: Jamixir.config()[:validator_count])

  @doc "WE - The basic size of our erasure-coded pieces."
  def erasure_coded_piece_size, do: 684

  @doc "WR - The maximum size of an encoded work-report in octets."
  def max_work_report_size, do: 48 * 2 ** 10

  @doc "WS - The size of an exported segment in erasure-coded pieces"
  def erasure_coded_exported_segment_size, do: 6

  @doc "Wc - The maximum size of service code in octets"
  def max_service_code_size, do: 4_000_000

  @doc "Wm - The maximum number of entries in a work-package manifest"
  def max_manifest_size, do: 2048

  @doc "Y - The number of timeslots into an epoch at which ticket-submission ends."
  defmockable(:ticket_submission_end, do: Jamixir.config()[:ticket_submission_end])

  # 4104
  def wswe, do: erasure_coded_piece_size() * erasure_coded_exported_segment_size()

  @doc "W_T - The size of the memo component in a deferred transfer, in octets."
  def memo_size, do: 128
end
