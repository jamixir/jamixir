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

  def add_block(state, %Block{header: h, extrinsic: e}) do
    todo = "TODO"
    # η'
    new_entropy_pool = update_entropy_pool(h, state.timeslot, state.entropy_pool)
    # ψ'
    new_judgements = update_judgements(h, e.judgements, state.judgements)
    # κ'
    new_curr_validators =
      update_curr_validators(
        h,
        state.timeslot,
        state.curr_validators,
        state.validator_keys,
        state.next_validators,
        new_judgements
      )

    %System.State{
      # α'
      authorization_requirements: todo,
      # β'
      recent_blocks: todo,
      # γ'
      validator_keys:
        update_validator_keys(
          h,
          state.timeslot,
          e.tickets,
          state.validator_keys,
          state.next_validators,
          new_entropy_pool,
          new_curr_validators
        ),
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
      # Equation (16) Equation (45) => τ' = Ht
      timeslot: h.timeslot,
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
end
