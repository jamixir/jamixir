defmodule System.State do
  alias Util.{Time, Hash}
  alias System.State.{Safrole, RecentBlock}

  @type t :: %__MODULE__{
          authorization_requirements: list(AuthorizationRequirement.t()),
          recent_blocks: list(RecentBlock.t()),
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
    :recent_blocks,
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
    beefy_commitment_map = "TODO"

    # Equation (16) Equation (45) => τ' = Ht
    new_timeslot = h.timeslot
    # β† Equation (17)
    initial_block_history =
      System.State.RecentBlock.get_initial_block_history(h, state.recent_blocks)

    # β' Equation (18)
    new_recent_blocks =
      update_recent_blocks(h, e.reports, initial_block_history, beefy_commitment_map)

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
        state.safrole,
        state.next_validators,
        new_judgements
      )

    # γ' Equation (19)
    new_safrole =
      update_safrole(
        h,
        state.timeslot,
        e.tickets,
        state.safrole,
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

  def update_entropy_pool(header, timeslot, %EntropyPool{
        current: current_entropy,
        history: history
      }) do
    new_entropy = Hash.blake2b_256(current_entropy <> entropy_vrf(header.vrf_signature))

    history =
      case Time.new_epoch?(timeslot, header.timeslot) do
        {:ok, true} ->
          [new_entropy | Enum.take(history, 2)]

        {:ok, false} ->
          history

        {:error, reason} ->
          raise "Error determining new epoch: #{reason}"
      end

    %EntropyPool{
      current: new_entropy,
      history: history
    }
  end

  defp update_judgements(_header, _judgements, _state_judgements) do
    # TODO
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

  defp update_safrole(
         _header,
         _timeslot,
         _tickets,
         _safrole,
         _next_validators,
         _entropy_pool,
         _curr_validators
       ) do
    # TODO
  end

  def entropy_vrf(value) do
    # TODO

    # for now, we will just return the value
    value
  end

  defp update_prev_validators(_header, _timeslot, _prev_validators, _curr_validators) do
    # TODO
  end

  defp update_recent_blocks(_header, _reports, _existing_recent_blocks, _beefy_commitment_map) do
    # TODO
  end
end
