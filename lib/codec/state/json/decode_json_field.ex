defmodule Codec.State.Json.DecodeField do
  alias System.State.{
    EntropyPool,
    RecentHistory,
    Services,
    ServiceAccount,
    Validator,
    ValidatorStatistics,
    Judgements,
    CoreReport,
    Safrole,
    Ready
  }

  def decode_field(:recent_blocks, value), do: decode_field(:beta, value)
  def decode_field(:auth_pools, value), do: decode_field(:alpha, value)
  def decode_field(:alpha, value), do: [{:authorizer_pool, JsonDecoder.from_json(value)}]
  def decode_field(:auth_queues, value), do: decode_field(:varphi, value)
  def decode_field(:varphi, value), do: [{:authorizer_queue, JsonDecoder.from_json(value)}]
  def decode_field(:beta, value), do: [{:recent_history, RecentHistory.from_json(value)}]
  def decode_field(:tau, value), do: [{:timeslot, value}]
  def decode_field(:slot, value), do: [{:timeslot, value}]
  def decode_field(:entropy, value), do: decode_field(:eta, value)
  def decode_field(:eta, value), do: [{:entropy_pool, EntropyPool.from_json(value)}]
  def decode_field(:accounts, value), do: [{:services, Services.from_json(value)}]

  def decode_field(:ready_queue, value),
    do: [
      {:ready_to_accumulate, for(queue <- value, do: for(r <- queue, do: Ready.from_json(r)))}
    ]

  def decode_field(:accumulated, value),
    do: [{:accumulation_history, Enum.map(value, &MapSet.new(JsonDecoder.from_json(&1)))}]

  def decode_field(:services, value),
    do: [
      {:services, for(s <- value, do: {s[:id], ServiceAccount.from_json(s[:info])}, into: %{})}
    ]

  def decode_field(:prev_validators, value), do: decode_field(:lambda, value)

  def decode_field(:lambda, value),
    do: [{:prev_validators, Enum.map(value, &Validator.from_json/1)}]

  def decode_field(:curr_validators, value), do: decode_field(:kappa, value)

  def decode_field(:kappa, value),
    do: [{:curr_validators, Enum.map(value, &Validator.from_json/1)}]

  def decode_field(:iota, value),
    do: [{:next_validators, Enum.map(value, &Validator.from_json/1)}]

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
  def decode_field(:psi, value), do: [{:judgements, Judgements.from_json(value)}]

  def decode_field(:pi, value),
    do: [{:validator_statistics, ValidatorStatistics.from_json(value)}]

  def decode_field(:avail_assignments, value), do: decode_field(:rho, value)

  def decode_field(:rho, value),
    do: [{:core_reports, Enum.map(value, &CoreReport.from_json/1)}]

  def decode_field(_, _), do: []

end
