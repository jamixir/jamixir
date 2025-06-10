defmodule System.State do
  alias System.State.Services
  alias System.State.Accumulation
  alias Block.Extrinsic.Assurance
  alias Block.Extrinsic.Guarantee
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Constants
  alias System.State
  alias System.State.{AuthorizerPool, CoreReport, EntropyPool, Judgements}
  alias System.State.{PrivilegedServices, Ready, RecentHistory, Safrole}
  alias System.State.{ServiceAccount, Validator, ValidatorStatistics}
  alias Util.Hash

  @type t :: %__MODULE__{
          # Formula (8.1) v0.6.6
          authorizer_pool: list(list(Types.hash())),
          recent_history: RecentHistory.t(),
          safrole: Safrole.t(),
          # Formula (9.1) v0.6.6
          # Formula (9.2) v0.6.6
          services: %{integer() => ServiceAccount.t()},
          entropy_pool: EntropyPool.t(),
          # Formula (6.7) v0.6.6
          next_validators: list(Validator.t()),
          curr_validators: list(Validator.t()),
          prev_validators: list(Validator.t()),
          core_reports: list(CoreReport.t() | nil),
          timeslot: integer(),
          # Formula (8.1) v0.6.6
          authorizer_queue: list(list(Types.hash())),
          privileged_services: PrivilegedServices.t(),
          judgements: Judgements.t(),
          validator_statistics: ValidatorStatistics.t(),
          # Formula (12.3) v0.6.6
          ready_to_accumulate: list(list(Ready.t())),
          # Formula (12.1) v0.6.6
          accumulation_history: list(MapSet.t(Types.hash()))
        }

  # Formula (4.4) v0.6.6 σ ≡ (α, β, γ, δ, η, ι, κ, λ, ρ, τ, φ, χ, ψ, π, ϑ, ξ)
  defstruct [
    # α
    authorizer_pool: List.duplicate([], Constants.core_count()),
    # β
    recent_history: %RecentHistory{},
    # γ
    safrole: %Safrole{},
    # δ
    services: %{},
    # η
    entropy_pool: %EntropyPool{},
    # ι
    next_validators: [],
    # κ
    curr_validators: [],
    # λ
    prev_validators: [],
    # ρ
    core_reports: CoreReport.initial_core_reports(),
    # τ
    timeslot: 0,
    # φ
    authorizer_queue:
      List.duplicate(
        List.duplicate(Hash.zero(), Constants.max_authorization_queue_items()),
        Constants.core_count()
      ),
    # χ
    privileged_services: %PrivilegedServices{},
    # ψ
    judgements: %Judgements{},
    # π
    validator_statistics: %ValidatorStatistics{},
    # ϑ
    ready_to_accumulate: Ready.initial_state(),
    # ξ
    accumulation_history: List.duplicate(MapSet.new(), Constants.epoch_length())
  ]

  # Formula (4.1) v0.6.6
  @spec add_block(System.State.t(), Block.t()) ::
          {:error, System.State.t(), :atom | String.t()} | {:ok, System.State.t()}
  def add_block(%State{} = state, %Block{header: h, extrinsic: e} = block) do
    # Formula (4.5) v0.6.6
    # Formula (6.1) v0.6.6
    timeslot_ = h.timeslot

    with :ok <- Block.validate(block, state),
         # ψ' Formula (4.11) v0.6.6
         {:ok, judgements_, bad_wonky_verdicts} <- Judgements.transition(h, e.disputes, state),
         # ρ† Formula (4.12) v0.6.6
         core_reports_1 = CoreReport.process_disputes(state.core_reports, bad_wonky_verdicts),
         available_work_reports = WorkReport.available_work_reports(e.assurances, core_reports_1),
         # ρ‡ Formula (4.13) v0.6.6
         core_reports_2 =
           CoreReport.process_availability(
             state.core_reports,
             core_reports_1,
             available_work_reports,
             h.timeslot
           ),
         :ok <-
           Guarantee.validate_availability(
             e.guarantees,
             core_reports_2,
             h.timeslot,
             state.authorizer_pool
           ),
         # ρ' Formula (4.14) v0.6.6
         core_reports_ = CoreReport.transition(core_reports_2, e.guarantees, timeslot_),
         # η' Formula (4.8) v0.6.6
         rotated_entropy_pool = EntropyPool.rotate(h, state.timeslot, state.entropy_pool),
         {curr_validators_, prev_validators_, safrole_} <-
           Safrole.transition(block, state, judgements_, rotated_entropy_pool),
         :ok <-
           Assurance.validate_assurances(
             e.assurances,
             h.parent_hash,
             h.timeslot,
             state.curr_validators,
             core_reports_1
           ),
         {:ok, %{vrf_signature_output: vrf_output}} <-
           System.HeaderSeal.validate_header_seals(
             h,
             curr_validators_,
             safrole_.slot_sealers,
             rotated_entropy_pool
           ),
         entropy_pool_ = EntropyPool.transition(vrf_output, rotated_entropy_pool),
         # Formula (4.15) v0.6.6 - W*
         # Formula (4.16) v0.6.6 - (ϑ',ξ',δ‡,χ',ι',φ',C)≺ (W∗,ϑ,ξ,δ,χ,ι,φ,τ,τ′)
         %{
           services: services_intermediate_2,
           next_validators: next_validators_,
           authorizer_queue: authorizer_queue_,
           ready_to_accumulate: ready_to_accumulate_,
           privileged_services: privileged_services_,
           accumulation_history: accumulation_history_,
           beefy_commitment: beefy_commitment_,
           accumulation_stats: accumulation_stats,
           deferred_transfers_stats: deferred_transfers_stats
         } =
           Accumulation.transition(
             available_work_reports,
             timeslot_,
             entropy_pool_.n0,
             state
           ),
         # δ' Formula (4.18) v0.6.6
         services_ = Services.transition(services_intermediate_2, e.preimages, timeslot_),
         # α' Formula (4.19) v0.6.6
         authorizer_pool_ =
           AuthorizerPool.transition(
             e.guarantees,
             authorizer_queue_,
             state.authorizer_pool,
             h.timeslot
           ),
         # β' Formula (4.17) v0.6.6
         recent_history_ =
           RecentHistory.transition(h, state.recent_history, e.guarantees, beefy_commitment_),
         {:ok, reporters_set} <-
           Guarantee.reporters_set(
             e.guarantees,
             entropy_pool_,
             timeslot_,
             curr_validators_,
             prev_validators_,
             Judgements.union_all(judgements_)
           ),
         # π' Formula (4.20) v0.6.6
         # π' ≺ (EG,EP,EA, ET,τ,κ',π,H)
         {:ok, validator_statistics_} <-
           ValidatorStatistics.transition(
             e,
             state.timeslot,
             {state.validator_statistics, accumulation_stats, deferred_transfers_stats},
             curr_validators_,
             h,
             reporters_set,
             available_work_reports
           ) do
      {:ok,
       %System.State{
         # α'
         authorizer_pool: authorizer_pool_,
         # β'
         recent_history: recent_history_,
         # γ'
         safrole: safrole_,
         # δ'
         services: services_,
         # η'
         entropy_pool: entropy_pool_,
         # ι'
         next_validators: next_validators_,
         # κ'
         curr_validators: curr_validators_,
         # λ'
         prev_validators: prev_validators_,
         # ρ'
         core_reports: core_reports_,
         # τ'
         timeslot: timeslot_,
         # φ'
         authorizer_queue: authorizer_queue_,
         # χ'
         privileged_services: privileged_services_,
         # ψ'
         judgements: judgements_,
         # π'
         validator_statistics: validator_statistics_,
         #  ξ'
         accumulation_history: accumulation_history_,
         #  ϑ'
         ready_to_accumulate: ready_to_accumulate_
       }}
    else
      {:error, reason} -> {:error, state, reason}
    end
  end

  def to_json_mapping do
    %{
      authorizer_pool: :alpha,
      recent_history: :beta,
      safrole: :gamma,
      services:
        {:delta,
         fn services ->
           for {id, service} <- services do
             %{id: id, data: service}
           end
         end},
      entropy_pool: :eta,
      next_validators: :iota,
      curr_validators: :kappa,
      prev_validators: :lambda,
      core_reports: :rho,
      timeslot: :tau,
      authorizer_queue: :varphi,
      privileged_services: :chi,
      judgements: :psi,
      validator_statistics: :pi,
      ready_to_accumulate: :theta,
      accumulation_history: :xi
    }
  end
end
