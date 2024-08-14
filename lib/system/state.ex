defmodule System.State do
  alias System.State

  alias System.State.{
    Validator,
    Judgements,
    Safrole,
    RecentHistory,
    EntropyPool,
    RotateKeys
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

  # Formula (15) v0.3.4 σ ≡ (α, β, γ, δ, η, ι, κ, λ, ρ, τ, φ, χ, ψ, π)
  defstruct [
    # α: Authorization requirement for work done on the core
    authorization_requirements: [],
    # β: Details of the most recent blocks
    recent_history: %RecentHistory{},
    # γ: State concerning the determination of validator keys
    safrole: %Safrole{},
    # δ: State dealing with services (analogous to smart contract accounts)
    services: [],
    # η: On-chain entropy pool
    entropy_pool: %EntropyPool{},
    # ι: Validators enqueued for next round
    next_validators: [],
    # κ: Current Validators
    curr_validators: [],
    # λ: Previous Validators
    prev_validators: [],
    # ρ: Each core's currently assigned report
    core_reports: [],
    # τ: Details of the most recent timeslot
    timeslot: 0,
    # φ: Queue which fills the authorization requirement
    authorization_queue: nil,
    # χ: Identities of services with privileged status
    privileged_services: [],
    # ψ: Judgements tracked
    judgements: %Judgements{},
    # π: Validator statistics
    validator_statistics: []
  ]

  # Formula (12) v0.3.4
  def add_block(state, %Block{header: h, extrinsic: e}) do
    todo = "TODO"

    # Formula (16) Formula (45) => τ' = Ht
    new_timeslot = h.timeslot
    # β† Formula (17) v0.3.4
    inital_recent_history =
      RecentHistory.update_latest_posterior_state_root(state.recent_history, h)

    # δ† Formula (24) v0.3.4
    # The post-preimage integration, pre-accumulation intermediate state
    services_intermediate =
      case Map.get(e, :preimages) do
        nil -> state.services
        [] -> state.services
        preimages -> State.Services.process_preimages(state.services, preimages, new_timeslot)
      end

    # ρ† Formula (25) v0.3.4
    # post-judgement, pre-assurances-extrinsic intermediate state
    core_reports_intermediate_1 =
      case Map.get(e, :disputes) do
        nil -> state.core_reports
        disputes -> State.CoreReports.process_disputes(state.core_reports, disputes)
      end

    # ρ‡ Formula (26) v0.3.4
    # The post-assurances-extrinsic, pre-guarantees-extrinsic, intermediate state
    core_reports_intermediate_2 =
      case Map.get(e, :availability) do
        nil ->
          core_reports_intermediate_1

        availability ->
          State.CoreReports.process_availability(core_reports_intermediate_1, availability)
      end

    # ρ' Formula (27) v0.3.4
    new_core_reports =
      case Map.get(e, :guarantees) do
        nil ->
          core_reports_intermediate_2

        _guarantees ->
          sorted_guarantees = Block.Extrinsic.unique_sorted_guarantees(e)

          State.CoreReports.posterior_core_reports(
            core_reports_intermediate_2,
            sorted_guarantees,
            state.curr_validators,
            new_timeslot
          )
      end

    # Formula (28) v0.3.4
    {_new_services, _privileged_services, _new_next_validators, _authorization_queue,
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

    # β' Formula (18) v0.3.4
    new_recent_history =
      case Map.get(e, :guarantees) do
        nil ->
          state.recent_history

        _guarantees ->
          sorted_guarantees = Block.Extrinsic.unique_sorted_guarantees(e)

          System.State.RecentHistory.posterior_recent_history(
            h,
            sorted_guarantees,
            inital_recent_history,
            beefy_commitment_map
          )
      end

    # η' Formula (20) v0.3.4
    new_entropy_pool =
      case Map.get(e, :entropy_pool) do
        nil -> state.entropy_pool
        _ -> EntropyPool.posterior_entropy_pool(h, state.timeslot, state.entropy_pool)
      end

    # ψ' Formula (23) v0.3.4
    new_judgements =
      case Map.get(e, :disputes) do
        nil -> state.judgements
        disputes -> Judgements.posterior_judgements(h, disputes, state)
      end

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
        pending: new_safrole_pending,
        epoch_root: new_safrole_epoch_root,
        current_epoch_slot_sealers: state.safrole.current_epoch_slot_sealers,
        ticket_accumulator: state.safrole.ticket_accumulator
      }

    # γ' Formula (19) v0.3.4
    new_safrole =
      case Map.get(e, :tickets) do
        nil ->
          intermediate_safrole

        tickets ->
          Safrole.posterior_safrole(
            h,
            state.timeslot,
            tickets,
            intermediate_safrole,
            state.next_validators,
            new_entropy_pool,
            new_curr_validators
          )
      end

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
end
