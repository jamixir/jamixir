defmodule State do
  @type t :: %__MODULE__{
          authorization_requirements: list(AuthorizationRequirement.t()),
          recent_blocks: list(RecentBlock.t()),
          validator_keys: list(ValidatorKey.t()),
          services: list(Service.t()),
          entropy_pool: EntropyPool.t(),
          enqueued_validators: list(Validator.t()),
          identified_validators: list(Validator.t()),
          archived_validators: list(Validator.t()),
          core_reports: list(CoreReport.t()),
          time: Util.Time.t(),
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
    # ι: Validators enqueued
    :enqueued_validators,
    # κ: Validators identified
    :identified_validators,
    # λ: Validators archived
    :archived_validators,
    # ρ: Each core's currently assigned report
    :core_reports,
    # τ: Details of the most recent time
    :time,
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
    new_entropy_pool = update_entropy_pool(h, state.time, state.entropy_pool)
    # ψ'
    new_judgements = update_judgements(h, e.judgements, state.judgements)
    # κ'
    new_identified_validators =
      update_identified_validators(
        h,
        state.time,
        state.identified_validators,
        state.validator_keys,
        state.enqueued_validators,
        new_judgements
      )

    %State{
      # α'
      authorization_requirements: todo,
      # β'
      recent_blocks: todo,
      # γ'
      validator_keys:
        update_validator_keys(
          h,
          state.time,
          e.tickets,
          state.validator_keys,
          state.enqueued_validators,
          new_entropy_pool,
          new_identified_validators
        ),
      # δ'
      services: todo,
      # η'
      entropy_pool: new_entropy_pool,
      # ι'
      enqueued_validators: todo,
      # κ'
      identified_validators: todo,
      # λ'
      archived_validators: todo,
      # ρ'
      core_reports: todo,
      # Equation (16) - τ'
      time: update_time(state.time, h),
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

  defp update_entropy_pool(header, time, entropy_pool) do
    # TODO
  end

  defp update_judgements(header, judgements, state_judgements) do
    # TODO
  end

  defp update_identified_validators(
         header,
         time,
         identified_validators,
         validator_keys,
         enqueued_validators,
         judgements
       ) do
    # TODO
  end

  defp update_validator_keys(
         header,
         time,
         tickets,
         validator_keys,
         enqueued_validators,
         entropy_pool,
         identified_validators
       ) do
    # TODO
  end

  defp update_time(time, header) do
    # TODO
  end
end
