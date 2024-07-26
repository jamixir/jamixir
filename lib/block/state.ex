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
    recent_time: RecentTime.t(),
    authorization_queue: AuthorizationQueue.t(),
    privileged_services: list(Identity.t()),
    judgements: list(Judgement.t()),
    validator_statistics: list(ValidatorStatistic.t())
  }

  defstruct [
	:authorization_requirements,  # α: Authorization requirement for work done on the core
	:recent_blocks,               # β: Details of the most recent blocks
	:validator_keys,              # γ: State concerning the determination of validator keys
	:services,                    # δ: State dealing with services (analogous to smart contract accounts)
	:entropy_pool,                # η: On-chain entropy pool
	:enqueued_validators,         # ι: Validators enqueued
	:identified_validators,       # κ: Validators identified
	:archived_validators,         # λ: Validators archived
	:core_reports,                # ρ: Each core's currently assigned report
	:recent_time,                 # τ: Details of the most recent time
	:authorization_queue,         # φ: Queue which fills the authorization requirement
	:privileged_services,         # χ: Identities of services with privileged status
	:judgements,                  # ψ: Judgements tracked
	:validator_statistics         # π: Validator statistics
  ]

  def add_block(state, %Block{header: h, extrinsic: e}) do
    todo = "TODO"
    %State{
      authorization_requirements: todo,  # α'
      recent_blocks: todo,               # β'
      validator_keys: todo,              # γ'
      services: todo,                    # δ'
      entropy_pool: update_entropy_pool(h, state.recent_time, state.entropy_pool),                # η'
      enqueued_validators: todo,         # ι'
      identified_validators: todo,       # κ'
      archived_validators: todo,         # λ'
      core_reports: todo,                # ρ'
      recent_time: update_time(state.recent_time, h), # Equation (16) - τ'
      authorization_queue: todo,         # φ'
      privileged_services: todo,         # χ'
      judgements: todo,                  # ψ'
      validator_statistics: todo        # π'
    }
  end

  defp update_entropy_pool(header, recent_time, entropy_pool) do
    #TODO
  end
  
  defp update_time(recent_time, header) do
    #TODO
  end

end