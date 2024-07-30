defmodule System.State do
  @type t :: %__MODULE__{
          authorization_requirements: list(AuthorizationRequirement.t()),
          recent_blocks: list(RecentBlock.t()),
          validator_keys: list(ValidatorKey.t()),
          services: list(Service.t()),
          entropy_pool: EntropyPool.t(),
          next_validators: list(Validator.t()),
          curr_validators: list(Validator.t()),
          prev_validators: list(Validator.t()),
          core_reports: list(CoreReport.t()),
          timeslot: Util.Time.t(),
          authorization_queue: AuthorizationQueue.t(),
          privileged_services: list(Identity.t()),
          judgements: list(Judgement.t()),
          validator_statistics: list(ValidatorStatistic.t())
        }

  # Equation (15) σ ≡ (α, β, γ, δ, η, ι, κ, λ, ρ, τ, φ, χ, ψ, π)
  defstruct [
    # α: Authorization requirement for work done on the core
    :authorization_requirements,
    # β: Details of the most recent blocks
    :recent_blocks,
    # γ: State concerning the determination of validator keys
    :validator_keys,
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
    beefy_commitment_map = "TODO"

    # Equation (16) Equation (45) => τ' = Ht
    new_timeslot = h.timeslot
    # Equation (17)
    initial_block_history = System.State.RecentBlock.get_initial_block_history(h, state.recent_blocks)
    # Equation (18)
    new_recent_blocks = update_recent_blocks(h, e.reports, initial_block_history, beefy_commitment_map)
    # η' Equation (20)
    new_entropy_pool = update_entropy_pool(h, state.timeslot, state.entropy_pool)
    # ψ' Equation (23)
    new_judgements = update_judgements(h, e.judgements, state.judgements)
    # κ' Equation (21)
    new_curr_validators =
      update_curr_validators(
        h,
        state.timeslot,
        state.curr_validators,
        state.validator_keys,
        state.next_validators,
        new_judgements
      )

    # γ' Equation (19)
    new_validator_keys =
      update_validator_keys(
        h,
        state.timeslot,
        e.tickets,
        state.validator_keys,
        state.next_validators,
        new_entropy_pool,
        new_curr_validators
      )

    # λ' Equation (22)
    new_prev_validators =
      update_prev_validators(h, state.timeslot, state.prev_validators, state.curr_validators)

    %System.State{
      # α'
      authorization_requirements: todo,
      # β'
      recent_blocks: new_recent_blocks,
      # γ'
      validator_keys: new_validator_keys,
      # δ'
      services: todo,
      # η'
      entropy_pool: new_entropy_pool,
      # ι'
      next_validators: todo,
      # κ'
      curr_validators: todo,
      # λ'
      prev_validators: todo,
      # ρ'
      core_reports: todo,
      # τ'
      timeslot: new_timeslot,
      # φ'
      authorization_queue: todo,
      # χ'
      privileged_services: todo,
      # ψ'
      judgements: todo,
      # π'
      validator_statistics: todo
    }
  end

  defp update_entropy_pool(header, timeslot, entropy_pool) do
    # TODO
  end

  defp update_judgements(header, judgements, state_judgements) do
    # TODO
  end

  defp update_curr_validators(
         header,
         timeslot,
         curr_validators,
         validator_keys,
         next_validators,
         judgements
       ) do
    # TODO
  end

  defp update_validator_keys(
         header,
         timeslot,
         tickets,
         validator_keys,
         next_validators,
         entropy_pool,
         curr_validators
       ) do
    # TODO
  end

  defp update_prev_validators(header, timeslot, prev_validators, curr_validators) do
    # TODO
  end

  defp update_recent_blocks(header, reports, existing_recent_blocks, beefy_commitment_map) do
    # TODO
  end

end
