defmodule System.State do
  alias Codec.NilDiscriminator
  use Codec.Encoder
  alias Block.Extrinsic.Assurance
  alias Block.Extrinsic.Guarantee
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Constants
  alias System.State

  alias System.State.{
    AuthorizerPool,
    CoreReport,
    EntropyPool,
    Judgements,
    PrivilegedServices,
    RecentHistory,
    RotateKeys,
    Safrole,
    ServiceAccount,
    Validator,
    ValidatorStatistics,
    Ready,
    WorkPackageRootMap
  }

  @type t :: %__MODULE__{
          # Formula (85) v0.4.1
          authorizer_pool: list(list(Types.hash())),
          recent_history: RecentHistory.t(),
          safrole: Safrole.t(),
          # Formula (88) v0.4.1 # TODO enforce key to be less than 2^32
          # Formula (89) v0.4.1
          services: %{integer() => ServiceAccount.t()},
          entropy_pool: EntropyPool.t(),
          # Formula (52) v0.4.1
          next_validators: list(Validator.t()),
          curr_validators: list(Validator.t()),
          prev_validators: list(Validator.t()),
          core_reports: list(CoreReport.t() | nil),
          timeslot: integer(),
          # Formula (85) v0.4.1
          authorizer_queue: list(list(Types.hash())),
          privileged_services: PrivilegedServices.t(),
          judgements: Judgements.t(),
          validator_statistics: ValidatorStatistics.t(),
          # Formula (158) v0.4.1
          accumulation_history: list(WorkPackageRootMap.t()),
          # Formula (160) v0.4.1
          ready_to_accumulate: list(list(Ready.t()))
        }

  # Formula (15) v0.4.1 σ ≡ (α, β, γ, δ, η, ι, κ, λ, ρ, τ, φ, χ, ψ, π)
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
    core_reports: CoreReport.initial_core_reports(),
    # τ: Details of the most recent timeslot
    timeslot: 0,
    # φ: Queue which fills the authorization requirement
    authorizer_queue: [[]],
    # χ: Identities of services with privileged status
    privileged_services: %PrivilegedServices{},
    # ψ: Judgements tracked
    judgements: %Judgements{},
    # π: Validator statistics
    validator_statistics: %ValidatorStatistics{},
    # ξ
    accumulation_history: WorkPackageRootMap.initial_state(),
    # ϑ
    ready_to_accumulate: Ready.initial_state()
  ]

  # Formula (12) v0.4.1
  @spec add_block(System.State.t(), Block.t()) :: {:error, System.State.t(), <<_::64, _::_*8>>}
  def add_block(%State{} = state, %Block{header: h, extrinsic: e} = block) do
    # Formula (16) v0.4.1
    # Formula (46) v0.4.1
    timeslot_ = h.timeslot

    with :ok <- Block.validate(block, state),
         # β† Formula (17) v0.4.1
         initial_recent_history =
           RecentHistory.update_latest_state_root_(state.recent_history, h),
         # δ† Formula (24) v0.4.1
         services_intermediate =
           State.Services.process_preimages(state.services, e.preimages, timeslot_),
         # ψ' Formula (23) v0.4.1
         {:ok, judgements_, bad_wonky_verdicts} <-
           Judgements.calculate_judgements_(h, e.disputes, state),
         # ρ† Formula (25) v0.4.1
         core_reports_intermediate_1 =
           State.CoreReport.process_disputes(state.core_reports, bad_wonky_verdicts),
         # ρ‡ Formula (26) v0.4.1
         core_reports_intermediate_2 =
           State.CoreReport.process_availability(
             state.core_reports,
             core_reports_intermediate_1,
             e.assurances
           ),
         :ok <-
           Guarantee.validate_availability(
             e.guarantees,
             core_reports_intermediate_2,
             h.timeslot,
             state.authorizer_pool
           ),
         # ρ' Formula (27) v0.4.1
         core_reports_ =
           State.CoreReport.calculate_core_reports_(
             core_reports_intermediate_2,
             e.guarantees,
             timeslot_
           ),
         available_work_reports =
           WorkReport.available_work_reports(e.assurances, core_reports_intermediate_1),
         # Formula (28) v0.4.1
         # Formula (29) v0.4.1
         {:ok, accumulation_result} <-
           State.Accumulation.accumulate(
             available_work_reports,
             h,
             state,
             services_intermediate
           ),
         # α' Formula (30) v0.4.1
         authorizer_pool_ =
           AuthorizerPool.calculate_authorizer_pool_(
             e.guarantees,
             accumulation_result.authorizer_queue,
             state.authorizer_pool,
             h.timeslot
           ),
         # β' Formula (18) v0.4.1
         recent_history_ =
           RecentHistory.calculate_recent_history_(
             h,
             e.guarantees,
             initial_recent_history,
             accumulation_result.beefy_commitment_map
           ),
         # κ' Formula (21) v0.4.1
         # λ' Formula (22) v0.4.1
         # γ'(gamma_k, gamma_z) Formula (19) v0.4.1
         {pending_, curr_validators_, prev_validators_, epoch_root_} =
           RotateKeys.rotate_keys(
             h,
             state.timeslot,
             state.prev_validators,
             state.curr_validators,
             state.next_validators,
             state.safrole,
             judgements_
           ),
         :ok <-
           Assurance.validate_assurances(
             e.assurances,
             h.parent_hash,
             curr_validators_,
             core_reports_intermediate_1
           ),

         # η' Formula (20) v0.4.1
         rotated_history_entropy_pool =
           EntropyPool.rotate_history(h, state.timeslot, state.entropy_pool),
         :ok <-
           System.Validators.Safrole.valid_epoch_marker(
             h,
             state.timeslot,
             rotated_history_entropy_pool.n1,
             pending_
           ),
         # Formula (69) v0.4.1
         epoch_slot_sealers_ =
           Safrole.get_epoch_slot_sealers_(
             h,
             state.timeslot,
             state.safrole,
             rotated_history_entropy_pool,
             curr_validators_
           ),
         # Formula (79) v0.4.1
         {:ok, ticket_accumulator_} <-
           Safrole.calculate_ticket_accumulator_(
             h.timeslot,
             state.timeslot,
             e.tickets,
             state.safrole,
             rotated_history_entropy_pool
           ),
         safrole_ = %Safrole{
           pending: pending_,
           epoch_root: epoch_root_,
           current_epoch_slot_sealers: epoch_slot_sealers_,
           ticket_accumulator: ticket_accumulator_
         },
         {:ok, %{vrf_signature_output: vrf_output}} <-
           System.HeaderSeal.validate_header_seals(
             h,
             curr_validators_,
             epoch_slot_sealers_,
             state.entropy_pool
           ),
         entropy_pool_ =
           EntropyPool.calculate_entropy_pool_(vrf_output, rotated_history_entropy_pool),
         {:ok, reporters_set} <-
           Guarantee.reporters_set(
             e.guarantees,
             entropy_pool_,
             timeslot_,
             curr_validators_,
             prev_validators_,
             Judgements.union_all(judgements_)
           ),
         # π' Formula (31) v0.4.1
         # π' ≺ (EG,EP,EA, ET,τ,κ',π,H)
         {:ok, validator_statistics_} <-
           ValidatorStatistics.calculate_validator_statistics_(
             e,
             state.timeslot,
             state.validator_statistics,
             curr_validators_,
             h,
             reporters_set
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
         services: accumulation_result.services,
         # η'
         entropy_pool: entropy_pool_,
         # ι'
         next_validators: accumulation_result.next_validators,
         # κ'
         curr_validators: curr_validators_,
         # λ'
         prev_validators: prev_validators_,
         # ρ'
         core_reports: core_reports_,
         # τ'
         timeslot: timeslot_,
         # φ'
         authorizer_queue: accumulation_result.authorizer_queue,
         # χ'
         privileged_services: accumulation_result.privileged_services,
         # ψ'
         judgements: judgements_,
         # π'
         validator_statistics: validator_statistics_,
         #  ξ'
         accumulation_history: accumulation_result.accumulation_history,
         #  ϑ'
         ready_to_accumulate: accumulation_result.ready_to_accumulate
       }}
    else
      {:error, reason} -> {:error, state, reason}
    end
  end

  # Formula (314) v0.4.1
  def state_keys(s) do
    %{
      # C(1) ↦ E([↕x ∣ x <− α])
      1 => e(for x <- s.authorizer_pool, do: vs(x)),
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
      10 => e(for c <- s.core_reports, do: NilDiscriminator.new(c)),
      # C(11) ↦ E4(τ)
      11 => e_le(s.timeslot, 4),
      # C(12) ↦ E4(χ)
      12 => e(s.privileged_services),
      # C(13) ↦ E4(π)
      13 => e(s.validator_statistics)
    }
    |> encode_accounts(s)
    |> encode_accounts_storage(s, :storage)
    |> encode_accounts_storage(s, :preimage_storage_p)
    |> encode_accounts_preimage_storage_l(s)
  end

  # Formula (313) v0.4.1 - C constructor
  # (i, s ∈ NS) ↦ [i, n0, n1, n2, n3, 0, 0, . . . ] where n = E4(s)
  def key_to_32_octet({i, s}) when i < 256 and s < 4_294_967_296 do
    <<i::8>> <> e_le(s, 4) <> <<0::216>>
  end

  # (s, h) ↦ [n0, h0, n1, h1, n2, h2, n3, h3, h4, h5, . . . , h27] where
  def key_to_32_octet({s, h}) do
    <<n0, n1, n2, n3>> = e_le(s, 4)
    <<h_part::binary-size(28), _rest::binary>> = h
    <<h0, h1, h2, h3, rest::binary>> = h_part
    <<n0, h0, n1, h1, n2, h2, n3, h3>> <> rest
  end

  # i ∈ N2^8 ↦ [i, 0, 0, . . . ]
  def key_to_32_octet(key) when key < 256, do: <<key::8, 0::248>>

  def serialize(state) do
    for {k, v} <- state_keys(state), do: {key_to_32_octet(k), v}, into: %{}
  end

  # ∀(s ↦ a) ∈ δ ∶ C(255, s) ↦ ac ⌢ E8(ab, ag, am, al) ⌢ E4(ai) ,
  defp encode_accounts(%{} = state_keys, %State{} = state) do
    state.services
    |> Enum.reduce(state_keys, fn {id, service}, ac ->
      Map.put(ac, {255, id}, e(service))
    end)
  end

  # ∀(s ↦ a) ∈ δ, (h ↦ v) ∈ as ∶ C(s, h) ↦ v
  # ∀(s ↦ a) ∈ δ, (h ↦ p) ∈ ap ∶ C(s, h) ↦ p
  defp encode_accounts_storage(state_keys, %State{} = state, property) do
    state.services
    |> Enum.reduce(state_keys, fn {s, a}, ac ->
      Map.get(a, property)
      |> Enum.reduce(ac, fn {h, v}, ac ->
        Map.put(ac, {s, h}, v)
      end)
    end)
  end

  # ∀(s ↦ a) ∈ δ, ((h, l) ↦ t) ∈ al ∶ C(s, E4(l) ⌢ (¬h4∶)) ↦ E(↕[E4(x) ∣ x <− t])
  defp encode_accounts_preimage_storage_l(state_keys, %State{} = state) do
    state.services
    |> Enum.reduce(state_keys, fn {s, a}, ac ->
      a.preimage_storage_l
      |> Enum.reduce(ac, fn {{h, l}, t}, ac ->
        value = e(vs(for x <- t, do: e_le(x, 4)))

        <<_::binary-size(4), rest::binary>> = h
        key = e_le(l, 4) <> Utils.invert_bits(rest)
        Map.put(ac, {s, key}, value)
      end)
    end)
  end

  def from_json(json) do
    decoded_fields =
      for {key, value} <- json,
          {struct_key, decoded_value} <- decode_json_field(key, value),
          into: %{} do
        {struct_key, decoded_value}
      end
      |> merge_safrole_fields()

    struct(%System.State{}, decoded_fields)
  end

  def from_genesis do
    case File.read("genesis.json") do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, json_data} ->
            {:ok, State.from_json(json_data |> Utils.atomize_keys())}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_json_field(:tau, value), do: [{:timeslot, value}]
  defp decode_json_field(:eta, value), do: [{:entropy_pool, EntropyPool.from_json(value)}]

  defp decode_json_field(:lambda, value),
    do: [{:prev_validators, Enum.map(value, &Validator.from_json/1)}]

  defp decode_json_field(:kappa, value),
    do: [{:curr_validators, Enum.map(value, &Validator.from_json/1)}]

  defp decode_json_field(:iota, value),
    do: [{:next_validators, Enum.map(value, &Validator.from_json/1)}]

  defp decode_json_field(:gamma_k, value), do: [{:safrole_pending, value}]
  defp decode_json_field(:gamma_z, value), do: [{:safrole_epoch_root, value}]
  defp decode_json_field(:gamma_s, value), do: [{:safrole_slot_sealers, value}]
  defp decode_json_field(:gamma_a, value), do: [{:safrole_ticket_accumulator, value}]
  defp decode_json_field(:psi, value), do: [{:judgements, Judgements.from_json(value)}]

  defp decode_json_field(:rho, value),
    do: [{:core_reports, Enum.map(value, &CoreReport.from_json/1)}]

  defp decode_json_field(_, _), do: []

  defp merge_safrole_fields(fields) do
    if fields[:safrole_pending] || fields[:safrole_epoch_root] ||
         fields[:safrole_slot_sealers] || fields[:safrole_ticket_accumulator] do
      safrole =
        Safrole.from_json(%{
          pending: fields[:safrole_pending],
          epoch_root: fields[:safrole_epoch_root],
          current_epoch_slot_sealers: fields[:safrole_slot_sealers],
          ticket_accumulator: fields[:safrole_ticket_accumulator]
        })

      fields
      |> Map.drop([
        :safrole_pending,
        :safrole_epoch_root,
        :safrole_slot_sealers,
        :safrole_ticket_accumulator
      ])
      |> Map.put(:safrole, safrole)
    else
      fields
    end
  end
end
