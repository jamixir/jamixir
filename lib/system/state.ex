defmodule System.State do
  alias Codec.NilDiscriminator
  alias Codec.VariableSize
  alias System.State

  alias System.State.{
    Validator,
    Judgements,
    Safrole,
    RecentHistory,
    EntropyPool,
    RotateKeys,
    ServiceAccount,
    CoreReports,
    PrivilegedServices,
    ValidatorStatistics
  }

  @type t :: %__MODULE__{
          # Formula (85) v0.3.4
          authorizer_pool: list(list(Types.hash())),
          recent_history: RecentHistory.t(),
          safrole: Safrole.t(),
          services: %{integer() => ServiceAccount.t()},
          entropy_pool: EntropyPool.t(),
          next_validators: list(Validator.t()),
          curr_validators: list(Validator.t()),
          prev_validators: list(Validator.t()),
          core_reports: CoreReports.t(),
          timeslot: integer(),
          # Formula (85) v0.3.4
          authorizer_queue: list(list(Types.hash())),
          privileged_services: PrivilegedServices.t(),
          judgements: Judgements.t(),
          validator_statistics: ValidatorStatistics.t()
        }

  # Formula (15) v0.3.4 σ ≡ (α, β, γ, δ, η, ι, κ, λ, ρ, τ, φ, χ, ψ, π)
  defstruct [
    # α: Authorization requirement for work done on the core
    authorizer_pool: [[]],
    # β: Details of the most recent blocks
    recent_history: %RecentHistory{},
    # γ: State concerning the determination of validator keys
    safrole: %Safrole{},
    # δ: State dealing with services (analogous to smart contract accounts)
    services: %{},
    # η: On-chain entropy pool
    entropy_pool: %EntropyPool{},
    # ι: Validators enqueued for next round
    next_validators: [],
    # κ: Current Validators
    curr_validators: [],
    # λ: Previous Validators
    prev_validators: [],
    # ρ: Each core's currently assigned report
    core_reports: %CoreReports{},
    # τ: Details of the most recent timeslot
    timeslot: 0,
    # φ: Queue which fills the authorization requirement
    authorizer_queue: [[]],
    # χ: Identities of services with privileged status
    privileged_services: %PrivilegedServices{},
    # ψ: Judgements tracked
    judgements: %Judgements{},
    # π: Validator statistics
    validator_statistics: %ValidatorStatistics{}
  ]

  # Formula (12) v0.3.4
  def add_block(state, %Block{header: h, extrinsic: e}) do
    todo = "TODO"

    # Formula (16) v0.3.4
    # Formula (46) v0.3.4
    new_timeslot = h.timeslot
    # β† Formula (17) v0.3.4
    inital_recent_history =
      RecentHistory.update_latest_posterior_state_root(state.recent_history, h)

    # δ† Formula (24) v0.3.4
    # The post-preimage integration, pre-accumulation intermediate state
    services_intermediate =
      State.Services.process_preimages(state.services, Map.get(e, :preimages), new_timeslot)

    # ρ† Formula (25) v0.3.4
    # post-judgement, pre-assurances-extrinsic intermediate state
    core_reports_intermediate_1 =
      State.CoreReports.process_disputes(state.core_reports, Map.get(e, :disputes))

    # ρ‡ Formula (26) v0.3.4
    # The post-assurances-extrinsic, pre-guarantees-extrinsic, intermediate state
    core_reports_intermediate_2 =
      State.CoreReports.process_availability(
        core_reports_intermediate_1,
        Map.get(e, :availability)
      )

    sorted_guarantees =
      Block.Extrinsic.unique_sorted_guarantees(e)

    # ρ' Formula (27) v0.3.4
    new_core_reports =
      State.CoreReports.posterior_core_reports(
        core_reports_intermediate_2,
        sorted_guarantees,
        state.curr_validators,
        new_timeslot
      )

    # Formula (28) v0.3.4
    {_new_services, _privileged_services, _new_next_validators, _authorizer_queue,
     beefy_commitment_map} =
      State.Accumulation.accumulate(
        Map.get(e, :availability),
        new_core_reports,
        services_intermediate,
        state.privileged_services,
        state.next_validators,
        state.authorizer_queue
      )

    # β' Formula (18) v0.3.4
    new_recent_history =
      System.State.RecentHistory.posterior_recent_history(
        h,
        sorted_guarantees,
        inital_recent_history,
        beefy_commitment_map
      )

    # η' Formula (20) v0.3.4
    new_entropy_pool =
      EntropyPool.posterior_entropy_pool(h, state.timeslot, state.entropy_pool)

    # ψ' Formula (23) v0.3.4
    new_judgements =
      Judgements.posterior_judgements(h, Map.get(e, :disputes), state)

    # κ' Formula (21) v0.3.4
    # λ' Formula (22) v0.3.4
    # γ'(gamma_k, gamma_z) Formula (19) v0.3.4
    {new_safrole_pending, new_curr_validators, new_prev_validators, new_safrole_epoch_root} =
      RotateKeys.rotate_keys(
        h,
        state.timeslot,
        state.prev_validators,
        state.curr_validators,
        state.next_validators,
        state.safrole,
        new_judgements
      )

    intermediate_safrole =
      %Safrole{
        state.safrole
        | pending: new_safrole_pending,
          epoch_root: new_safrole_epoch_root
      }

    # γ' Formula (19) v0.3.4
    new_safrole =
      Safrole.posterior_safrole(
        h,
        state.timeslot,
        Map.get(e, :tickets),
        intermediate_safrole,
        new_entropy_pool,
        new_curr_validators
      )

    %System.State{
      # α'
      authorizer_pool: todo,
      # β'
      recent_history: new_recent_history,
      # γ'
      safrole: new_safrole,
      # δ'
      services: todo,
      # η'
      entropy_pool: new_entropy_pool,
      # ι'
      next_validators: todo,
      # κ'
      curr_validators: new_curr_validators,
      # λ'
      prev_validators: new_prev_validators,
      # ρ'
      core_reports: todo,
      # τ'
      timeslot: new_timeslot,
      # φ'
      authorizer_queue: todo,
      # χ'
      privileged_services: todo,
      # ψ'
      judgements: new_judgements,
      # π'
      validator_statistics: todo
    }
  end

  def e(v), do: Codec.Encoder.encode(v)

  # Formula (292) v0.3.4
  def state_keys(s) do
    %{
      # C(1) ↦ E([↕x ∣ x <− α])
      1 => e(s.authorizer_pool |> Enum.map(&VariableSize.new/1)),
      # C(2) ↦ E(φ)
      2 => e(s.authorizer_queue),
      # C(3) ↦ E(↕[(h, EM (b), s, ↕p) ∣ (h, b, s, p) <− β])
      3 => e(s.recent_history),
      # C(4) - safrole encoding
      4 => e(s.safrole),
      # C(5) ↦ judgements encoding
      5 => e(s.judgements),
      # C(6) ↦ E(η)
      6 => e(s.entropy_pool),
      # C(7) ↦ E(ι)
      7 => e(s.next_validators),
      # C(8) ↦ E(κ)
      8 => e(s.curr_validators),
      # C(9) ↦ E(λ)
      9 => e(s.prev_validators),
      # C(10) ↦ E([¿(w, E4(t)) ∣ (w, t) <− ρ])
      10 => e(s.core_reports.reports |> Enum.map(&NilDiscriminator.new/1)),
      # C(11) ↦ E4(τ)
      11 => Codec.Encoder.encode_le(s.timeslot, 4),
      # C(12) ↦ E4(χ)
      12 => Codec.Encoder.encode(s.privileged_services),
      # C(13) ↦ E4(π)
      13 => Codec.Encoder.encode(s.validator_statistics)
    }
    |> encode_accounts(s)
  end

  defp encode_accounts(%{} = state_keys, state = %State{}) do
    state.services
    |> Enum.reduce(state_keys, fn {id, service}, ac ->
      Map.put(ac, {255, id}, Codec.Encoder.encode(service))
    end)
  end
end
