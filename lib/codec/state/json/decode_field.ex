defmodule Codec.State.Json.DecodeField do
  alias System.State.PrivilegedServices

  alias System.State.{
    EntropyPool,
    RecentHistory,
    Services,
    Validator,
    ValidatorStatistics,
    Judgements,
    CoreReport,
    Safrole,
    Ready
  }

  # σ ≡ (α, β, γ, δ, η, ι, κ, λ, ρ, τ, φ, χ, ψ, π, ω, ξ)
  def decode_field(:alpha, value), do: [{:authorizer_pool, JsonDecoder.from_json(value)}]
  def decode_field(:beta, value), do: [{:recent_history, RecentHistory.from_json(value)}]

  def decode_field(:gamma, value),
    do: [
      {:safrole,
       Safrole.from_json(%{
         pending: value[:gamma_k],
         epoch_root: value[:gamma_z],
         slot_sealers: value[:gamma_s],
         ticket_accumulator: value[:gamma_a]
       })}
    ]

  def decode_field(:gamma_k, value), do: [{:safrole_pending, value}]
  def decode_field(:gamma_z, value), do: [{:safrole_epoch_root, value}]
  def decode_field(:gamma_s, value), do: [{:safrole_slot_sealers, value}]
  def decode_field(:gamma_a, value), do: [{:safrole_ticket_accumulator, value}]

  def decode_field(:delta, value), do: [{:services, Services.from_json(value)}]
  def decode_field(:eta, value), do: [{:entropy_pool, EntropyPool.from_json(value)}]

  def decode_field(:iota, value),
    do: [{:next_validators, Enum.map(value, &Validator.from_json/1)}]

  def decode_field(:kappa, value),
    do: [{:curr_validators, Enum.map(value, &Validator.from_json/1)}]

  def decode_field(:lambda, value),
    do: [{:prev_validators, Enum.map(value, &Validator.from_json/1)}]

  def decode_field(:rho, value), do: [{:core_reports, Enum.map(value, &CoreReport.from_json/1)}]
  def decode_field(:tau, value), do: [{:timeslot, value}]
  def decode_field(:varphi, value), do: [{:authorizer_queue, JsonDecoder.from_json(value)}]
  def decode_field(:chi, value), do: [{:privileged_services, PrivilegedServices.from_json(value)}]

  def decode_field(:psi, value), do: [{:judgements, Judgements.from_json(value)}]

  def decode_field(:statistics, value),
    do: [{:validator_statistics, ValidatorStatistics.from_json(value)}]

  def decode_field(:pi, value),
    do: [{:validator_statistics, ValidatorStatistics.from_json(value)}]

  def decode_field(:theta, value),
    do: [
      {:ready_to_accumulate, for(queue <- value, do: for(r <- queue, do: Ready.from_json(r)))}
    ]

  def decode_field(:xi, value),
    do: [{:accumulation_history, Enum.map(value, &MapSet.new(JsonDecoder.from_json(&1)))}]

  # secondry names
  # alpha - auth_pool
  def decode_field(:auth_pools, value), do: decode_field(:alpha, value)
  # beta - recent_blocks
  def decode_field(:recent_blocks, value), do: decode_field(:beta, value)

  # delta - services
  def decode_field(:accounts, value), do: decode_field(:delta, value)

  # eta - entropy
  def decode_field(:entropy, value), do: decode_field(:eta, value)

  # kappa - curr_validators
  def decode_field(:curr_validators, value), do: decode_field(:kappa, value)

  # lambda - prev_validators
  def decode_field(:prev_validators, value), do: decode_field(:lambda, value)

  # rho - core assignments
  def decode_field(:avail_assignments, value), do: decode_field(:rho, value)

  # tau - timeslot
  def decode_field(:slot, value), do: decode_field(:tau, value)

  # varphi - auth_queue
  def decode_field(:auth_queues, value), do: decode_field(:varphi, value)

  # theta - ready_queue
  def decode_field(:ready_queue, value), do: decode_field(:theta, value)

  # xi - accumulated
  def decode_field(:accumulated, value), do: decode_field(:xi, value)

  def decode_field(_, _), do: []
end
