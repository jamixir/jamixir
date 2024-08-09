defmodule System.State do
  alias System.State

  alias System.State.{
    Validator,
    Judgements,
    Safrole,
    RecentHistory,
    EntropyPool
  }

  @type t :: %__MODULE__{
          authorization_requirements: list(AuthorizationRequirement.t()),
          recent_history: RecentHistory.t(),
          safrole: Safrole.t(),
          services: list(Service.t()),
          entropy_pool: EntropyPool.t(),
          next_validators: list(Validator.t()),
          curr_validators: list(Validator.t()),
          prev_validators: list(Validator.t()),
          core_reports: list(CoreReport.t()),
          timeslot: integer(),
          authorization_queue: AuthorizationQueue.t(),
          privileged_services: list(Identity.t()),
          judgements: Judgements.t(),
          validator_statistics: list(ValidatorStatistic.t())
        }

  # Equation (15) σ ≡ (α, β, γ, δ, η, ι, κ, λ, ρ, τ, φ, χ, ψ, π)
  defstruct [
    # α: Authorization requirement for work done on the core
    :authorization_requirements,
    # β: Details of the most recent blocks
    :recent_history,
    # γ: State concerning the determination of validator keys
    :safrole,
    # δ: State dealing with services (analogous to smart contract accounts)
    :services,
    # η: On-chain entropy pool
    :entropy_pool,
    # ι: Validators enqueued for next round
    :next_validators,
    # κ: Current Validators
    :curr_validators,
    # λ: Previous Validators
    :prev_validators,
    # ρ: Each core's currently assigned report
    :core_reports,
    # τ: Details of the most recent timeslot
    :timeslot,
    # φ: Queue which fills the authorization requirement
    :authorization_queue,
    # χ: Identities of services with privileged status
    :privileged_services,
    # ψ: Judgements tracked
    :judgements,
    # π: Validator statistics
    :validator_statistics
  ]

  # Equation (12)
  def add_block(state, %Block{header: h, extrinsic: e}) do
    todo = "TODO"

    # Equation (16) Equation (45) => τ' = Ht
    new_timeslot = h.timeslot
    # β† Equation (17)
    inital_recent_history =
      RecentHistory.update_latest_posterior_state_root(state.recent_history, h)

    # δ† Equation (24)
    # The post-preimage integration, pre-accumulation intermediate state

    services_intermediate =
      case Map.get(e, :preimages) do
        nil -> state.services
        [] -> state.services
        preimages -> State.Services.process_preimages(state.services, preimages, new_timeslot)
      end

    # ρ† Equation (25)
    # post-judgement, pre-assurances-extrinsic intermediate state

    core_reports_intermediate_1 =
      case Map.get(e, :disputes) do
        nil -> state.core_reports
        disputes -> State.CoreReports.process_disputes(state.core_reports, disputes)
      end

    # ρ‡ Equation (26)
    # The post-assurances-extrinsic, pre-guarantees-extrinsic, intermediate state
    core_reports_intermediate_2 =
      case Map.get(e, :availability) do
        nil ->
          core_reports_intermediate_1

        availability ->
          State.CoreReports.process_availability(core_reports_intermediate_1, availability)
      end

    # ρ' Equation (27)

    new_core_reports =
      case Map.get(e, :guarantees) do
        nil ->
          core_reports_intermediate_2

        guarantees ->
          State.CoreReports.posterior_core_reports(
            core_reports_intermediate_2,
            guarantees,
            state.curr_validators,
            new_timeslot
          )
      end

    # The service accumulation-commitment / beefy-commitment map
    # Equation (28)

    {new_services, privileged_services, new_next_validators, authorization_queue,
     beefy_commitment_map} =
      case Map.get(e, :availability) do
        nil ->
          {
            services_intermediate,
            state.privileged_services,
            state.next_validators,
            state.authorization_queue,
            System.State.BeefyCommitmentMap.stub()
          }

        availability ->
          State.Accumulation.accumulate(
            availability,
            new_core_reports,
            services_intermediate,
            state.privileged_services,
            state.next_validators,
            state.authorization_queue
          )
      end

    # β' Equation (18)
    new_recent_history =
      case Map.get(e, :guarantees) do
        nil ->
          state.recent_history

        guarantees ->
          System.State.RecentHistory.posterior_recent_history(
            h,
            guarantees,
            inital_recent_history,
            beefy_commitment_map
          )
      end

    # η' Equation (20)
    new_entropy_pool =
      case Map.get(e, :entropy_pool) do
        nil -> state.entropy_pool
        _ -> EntropyPool.posterior_entropy_pool(h, state.timeslot, state.entropy_pool)
      end

    # ψ' Equation (23)
    new_judgements =
      case Map.get(e, :disputes) do
        nil -> state.judgements
        disputes -> Judgements.posterior_judgements(h, disputes, state)
      end

    # κ' Equation (21)
    new_curr_validators =
      update_curr_validators(
        h,
        state.timeslot,
        state.curr_validators,
        state.safrole,
        state.next_validators,
        new_judgements
      )

    # γ' Equation (19)
    new_safrole =
      case Map.get(e, :tickets) do
        nil ->
          state.safrole

        tickets ->
          Safrole.posterior_safrole(
            h,
            state.timeslot,
            tickets,
            state.safrole,
            state.next_validators,
            new_entropy_pool,
            new_curr_validators
          )
      end

    # λ' Equation (22)
    new_prev_validators =
      update_prev_validators(h, state.timeslot, state.prev_validators, state.curr_validators)

    %System.State{
      # α'
      authorization_requirements: todo,
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
      authorization_queue: todo,
      # χ'
      privileged_services: todo,
      # ψ'
      judgements: new_judgements,
      # π'
      validator_statistics: todo
    }
  end

  defp update_curr_validators(
         _header,
         _timeslot,
         _curr_validators,
         _safrole,
         _next_validators,
         _judgements
       ) do
    # TODO
  end

  defp update_prev_validators(_header, _timeslot, _prev_validators, _curr_validators) do
    # TODO
  end
end
