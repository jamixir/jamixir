defmodule Constants do
  use Mockable

  @moduledoc """
  A module to hold constants used throughout the system.
  see Appendix I.3 of the GP for more information.
  """

  @doc "The period, in seconds, between audit tranches."
  def audit_trenches_period, do: 8

  @spec additional_minimum_balance_per_item() :: Types.balance()
  @doc "B_I = The additional minimum balance required per item of elective service state."
  def additional_minimum_balance_per_item, do: 10

  @spec additional_minimum_balance_per_octet() :: Types.balance()
  @doc "B_L = The additional minimum balance required per octet of elective service state."
  def additional_minimum_balance_per_octet, do: 1

  @spec service_minimum_balance() :: Types.balance()
  @doc "B_S = The basic minimum balance which all services require."
  def service_minimum_balance, do: 100

  @doc "C - total number of cores"
  defmockable(:core_count, do: Jamixir.config()[:core_count])

  @doc "D - The period in timeslots after which an unreferenced preimage may be expunged"
  defmockable(:forget_delay, do: 28_800)

  @doc "E - The length of an epoch in timeslots."
  defmockable(:epoch_length, do: Jamixir.config()[:epoch_length])

  @doc "G_A - The total gas allocated to a core for Accumulation."
  defmockable(:gas_accumulation, do: Jamixir.config(:gas_accumulation))

  @doc "G_I : The gas allocated to invoke a work-package's Is-Authorized logic."
  defmockable(:gas_is_authorized, do: 50_000_000)

  @doc "G_R: The total gas allocated for a work-package's Refine logic."
  defmockable(:gas_refine, do: 5_000_000_000)

  @doc "G_T: The total gas allocated across all cores for Accumulation."
  defmockable(:gas_total_accumulation, do: 3_500_000_000)

  @doc "H - The size of recent history, in blocks."
  defmockable(:recent_history_size, do: 8)

  @doc "I - The maximum amount of work items in a package."
  def max_work_items, do: 16

  @doc "J - The maximum sum of dependency items in a work-report."
  defmockable(:max_work_report_dep_sum, do: 8)

  @doc "K - The maximum number of tickets which may be submitted in a single extrinsic."
  defmockable(:max_tickets_pre_extrinsic, do: Jamixir.config()[:max_tickets_pre_extrinsic])

  @doc "L = 14, 400: The maximum age in timeslots of the lookup anchor."
  def max_age_lookup_anchor, do: 14_400

  @doc "N - The number of ticket entries per validator"
  defmockable(:tickets_per_validator, do: Jamixir.config(:tickets_per_validator))

  @doc "O - The maximum number of items in the authorizations pool."
  def max_authorizations_items, do: 8

  @doc "P - The timeslot period, in seconds."
  def slot_period, do: Jamixir.config()[:slot_period] || 6

  @doc "Q - The maximum number of items in the authorization queue."
  def max_authorization_queue_items, do: 80

  @doc "R - The rotation period of validator-core assignments, in timeslots."
  defmockable(:rotation_period, do: Jamixir.config(:rotation_period))

  @doc "S - The maximum number of entries in the accumulation queue."
  def max_accumulation_queue_items, do: 1024

  @doc "T - The maximum number of extrinsics in a work-package."
  def max_extrinsics, do: 128

  @doc "U - The period in timeslots after which reported but unavailable work may be replaced."
  def unavailability_period, do: 5

  @doc "V - The total number of validators."
  defmockable(:validator_count, do: Jamixir.config(:validator_count))

  @doc "W_A - The maximum size of is-authorized code in octets"
  def max_is_authorized_code_size, do: 64_000

  # Formula (14.6) v0.6.5 - WB
  @doc "W_B = 12 * 2^20: The maximum size of an encoded work-package together with its extrinsic data and import implications, in octets"
  def max_work_package_size, do: 12_582_912

  @doc "W_C - The maximum size of service code in octets"
  def max_service_code_size, do: 4_000_000

  @doc "W_E - The basic size of our erasure-coded pieces."
  def erasure_coded_piece_size, do: Jamixir.config()[:ec_size] || 684

  @doc "W_G = W_P W_E = 4104: The size of a segment in octets."
  def segment_size, do: erasure_coded_piece_size() * erasure_coded_exported_segment_size()

  @doc "W_M - The maximum number of imports and exports in a work-package"
  def max_imports, do: 3_072

  @doc "W_P - The number of erasure-coded pieces in a segment."
  def erasure_coded_pieces_per_segment, do: 6

  @doc "W_R - The maximum size of an encoded work-report in octets."
  def max_work_report_size, do: 48 * 2 ** 10

  @doc "W_S - The size of an exported segment in erasure-coded pieces"
  def erasure_coded_exported_segment_size, do: 6

  @doc "W_T - The size of the memo component in a deferred transfer, in octets."
  def memo_size, do: 128

  @doc "W_X - The maximum number of exports in a work-package"
  def max_exports, do: 3_072

  @doc "Y - The number of timeslots into an epoch at which ticket-submission ends."
  defmockable(:ticket_submission_end, do: Jamixir.config(:ticket_submission_end))
end
