defmodule System.State do
  alias System.State.Services
  alias System.State.Accumulation
  alias Codec.NilDiscriminator
  use Codec.Encoder
  import Bitwise
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
          # Formula (85) v0.4.5
          authorizer_pool: list(list(Types.hash())),
          recent_history: RecentHistory.t(),
          safrole: Safrole.t(),
          # Formula (88) v0.4.5 # TODO enforce key to be less than 2^32
          # Formula (89) v0.4.5
          services: %{integer() => ServiceAccount.t()},
          entropy_pool: EntropyPool.t(),
          # Formula (52) v0.4.5
          next_validators: list(Validator.t()),
          curr_validators: list(Validator.t()),
          prev_validators: list(Validator.t()),
          core_reports: list(CoreReport.t() | nil),
          timeslot: integer(),
          # Formula (85) v0.4.5
          authorizer_queue: list(list(Types.hash())),
          privileged_services: PrivilegedServices.t(),
          judgements: Judgements.t(),
          validator_statistics: ValidatorStatistics.t(),
          # Formula (162) v0.4.5
          accumulation_history: list(MapSet.t(Types.hash())),
          # Formula (164) v0.4.5
          ready_to_accumulate: list(list(Ready.t()))
        }

  # Formula (15) v0.4.5 σ ≡ (α, β, γ, δ, η, ι, κ, λ, ρ, τ, φ, χ, ψ, π)
  defstruct [
    # α: Authorization requirement for work done on the core
    authorizer_pool: List.duplicate([], Constants.core_count()),
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
    authorizer_queue:
      List.duplicate(
        List.duplicate(Hash.zero(), Constants.max_authorization_queue_items()),
        Constants.core_count()
      ),
    # χ: Identities of services with privileged status
    privileged_services: %PrivilegedServices{},
    # ψ: Judgements tracked
    judgements: %Judgements{},
    # π: Validator statistics
    validator_statistics: %ValidatorStatistics{},
    # ξ
    accumulation_history: List.duplicate(MapSet.new(), Constants.epoch_length()),
    # ϑ
    ready_to_accumulate: Ready.initial_state()
  ]

  # Formula (12) v0.4.5
  @spec add_block(System.State.t(), Block.t()) ::
          {:error, System.State.t(), :atom | String.t()} | {:ok, System.State.t()}
  def add_block(%State{} = state, %Block{header: h, extrinsic: e} = block) do
    # Formula (16) v0.4.5
    # Formula (46) v0.4.5
    timeslot_ = h.timeslot

    with :ok <- Block.validate(block, state),
         # ψ' Formula (23) v0.4.5
         {:ok, judgements_, bad_wonky_verdicts} <- Judgements.transition(h, e.disputes, state),
         # ρ† Formula (25) v0.4.5
         core_reports_1 = CoreReport.process_disputes(state.core_reports, bad_wonky_verdicts),
         # ρ‡ Formula (26) v0.4.5
         core_reports_2 =
           CoreReport.process_availability(
             state.core_reports,
             core_reports_1,
             e.assurances,
             h.timeslot
           ),
         :ok <-
           Guarantee.validate_availability(
             e.guarantees,
             core_reports_2,
             h.timeslot,
             state.authorizer_pool
           ),
         # ρ' Formula (27) v0.4.5
         core_reports_ = CoreReport.transition(core_reports_2, e.guarantees, timeslot_),
         available_work_reports = WorkReport.available_work_reports(e.assurances, core_reports_1),
         # Formula (4.16) v0.5
         # Formula (4.17) v0.5
         {:ok,
          %{
            services: services_intermediate_2,
            next_validators: next_validators_,
            authorizer_queue: authorizer_queue_,
            ready_to_accumulate: ready_to_accumulate_,
            privileged_services: privileged_services_,
            accumulation_history: accumulation_history_,
            beefy_commitment: beefy_commitment_
          }} <-
           Accumulation.transition(available_work_reports, timeslot_, state),
         # δ' Formula (4.18) v0.5
         services_ = Services.transition(services_intermediate_2, e.preimages, timeslot_),
         # α' Formula (30) v0.4.5
         authorizer_pool_ =
           AuthorizerPool.transition(
             e.guarantees,
             authorizer_queue_,
             state.authorizer_pool,
             h.timeslot
           ),
         # η' Formula (20) v0.4.5
         rotated_entropy_pool = EntropyPool.rotate(h, state.timeslot, state.entropy_pool),
         # β' Formula (18) v0.4.5
         recent_history_ =
           RecentHistory.transition(h, state.recent_history, e.guarantees, beefy_commitment_),
         {curr_validators_, prev_validators_, safrole_} <-
           Safrole.transition(block, state, judgements_, rotated_entropy_pool),
         :ok <-
           Assurance.validate_assurances(
             e.assurances,
             h.parent_hash,
             h.timeslot,
             curr_validators_,
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
         {:ok, reporters_set} <-
           Guarantee.reporters_set(
             e.guarantees,
             entropy_pool_,
             timeslot_,
             curr_validators_,
             prev_validators_,
             Judgements.union_all(judgements_)
           ),
         # π' Formula (31) v0.4.5
         # π' ≺ (EG,EP,EA, ET,τ,κ',π,H)
         {:ok, validator_statistics_} <-
           ValidatorStatistics.transition(
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

  # # Formula (D.2) v0.5
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
      13 => e(s.validator_statistics),
      14 => e(for x <- s.accumulation_history, do: vs(x)),
      15 => e(for x <- s.ready_to_accumulate, do: vs(x))
    }
    |> encode_accounts(s)
    |> encode_accounts_storage_s(s, :storage)
    |> encode_accounts_storage_p(s, :preimage_storage_p)
    |> encode_accounts_preimage_storage_l(s)
  end

  # Formula (D.1) v0.5 - C constructor
  # (i, s ∈ NS) ↦ [i, n0, 0, n1, 0, n2, 0, n3, 0, 0, . . . ] where n = E4(s)
  def key_to_32_octet({i, s}) when i < 256 and s < 4_294_967_296 do
    <<n0, n1, n2, n3>> = e_le(s, 4)
    <<i::8>> <> <<n0, 0, n1, 0, n2, 0, n3, 0>> <> <<0::184>>
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
    for({k, v} <- state_keys(state), do: {key_to_32_octet(k), v}, into: %{})
  end

  def serialize_hex(state) do
    for {k, v} <- serialize(state), do: {Base.encode16(k), Base.encode16(v)}, into: %{}
  end

  # ∀(s ↦ a) ∈ δ ∶ C(255, s) ↦ ac ⌢ E8(ab, ag, am, al) ⌢ E4(ai) ,
  defp encode_accounts(%{} = state_keys, %State{} = state) do
    state.services
    |> Enum.reduce(state_keys, fn {id, service}, ac ->
      Map.put(ac, {255, id}, e(service))
    end)
  end

  # ∀(s ↦ a) ∈ δ, (k ↦ v) ∈ as ∶ C(s, E4 (2^32 − 1) ⌢ k0...28 ) ↦ v
  defp encode_accounts_storage_s(state_keys, %State{} = state, property) do
    state.services
    |> Enum.reduce(state_keys, fn {s, a}, ac ->
      Map.get(a, property)
      |> Enum.reduce(ac, fn {h, v}, ac ->
        Map.put(ac, {s, e_le((1 <<< 32) - 1, 4) <> binary_slice(h, 0, 28)}, v)
      end)
    end)
  end

  # ∀(s ↦ a) ∈ δ, (h ↦ p) ∈ ap ∶ C(s, E4 (2^32 − 2) ⌢ h1...29 ) ↦ p
  defp encode_accounts_storage_p(state_keys, %State{} = state, property) do
    state.services
    |> Enum.reduce(state_keys, fn {s, a}, ac ->
      Map.get(a, property)
      |> Enum.reduce(ac, fn {h, v}, ac ->
        Map.put(ac, {s, e_le((1 <<< 32) - 2, 4) <> binary_slice(h, 1, 28)}, v)
      end)
    end)
  end

  # ∀(s ↦ a) ∈ δ, ((h, l) ↦ t) ∈ al ∶ C(s, E4 (l) ⌢ H(h)2...30 ) ↦ E(↕[E4 (x) ∣ x −< t])
  defp encode_accounts_preimage_storage_l(state_keys, %State{} = state) do
    state.services
    |> Enum.reduce(state_keys, fn {s, a}, ac ->
      a.preimage_storage_l
      |> Enum.reduce(ac, fn {{h, l}, t}, ac ->
        value = e(vs(for x <- t, do: e_le(x, 4)))
        key = (e_le(l, 4) <> Hash.default(h)) |> binary_slice(2, 28)
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

  def from_genesis(file \\ "genesis.json") do
    case File.read(file) do
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

  defp decode_json_field(:recent_blocks, value), do: decode_json_field(:beta, value)
  defp decode_json_field(:auth_pools, value), do: decode_json_field(:alpha, value)
  defp decode_json_field(:alpha, value), do: [{:authorizer_pool, JsonDecoder.from_json(value)}]
  defp decode_json_field(:auth_queues, value), do: decode_json_field(:varphi, value)
  defp decode_json_field(:varphi, value), do: [{:authorizer_queue, JsonDecoder.from_json(value)}]
  defp decode_json_field(:beta, value), do: [{:recent_history, RecentHistory.from_json(value)}]
  defp decode_json_field(:tau, value), do: [{:timeslot, value}]
  defp decode_json_field(:slot, value), do: [{:timeslot, value}]
  defp decode_json_field(:entropy, value), do: decode_json_field(:eta, value)
  defp decode_json_field(:eta, value), do: [{:entropy_pool, EntropyPool.from_json(value)}]
  defp decode_json_field(:accounts, value), do: [{:services, Services.from_json(value)}]

  defp decode_json_field(:ready_queue, value),
    do: [
      {:ready_to_accumulate, for(queue <- value, do: for(r <- queue, do: Ready.from_json(r)))}
    ]

  defp decode_json_field(:accumulated, value),
    do: [{:accumulation_history, Enum.map(value, &MapSet.new(JsonDecoder.from_json(&1)))}]

  defp decode_json_field(:services, value),
    do: [
      {:services, for(s <- value, do: {s[:id], ServiceAccount.from_json(s[:info])}, into: %{})}
    ]

  defp decode_json_field(:prev_validators, value), do: decode_json_field(:lambda, value)

  defp decode_json_field(:lambda, value),
    do: [{:prev_validators, Enum.map(value, &Validator.from_json/1)}]

  defp decode_json_field(:curr_validators, value), do: decode_json_field(:kappa, value)

  defp decode_json_field(:kappa, value),
    do: [{:curr_validators, Enum.map(value, &Validator.from_json/1)}]

  defp decode_json_field(:iota, value),
    do: [{:next_validators, Enum.map(value, &Validator.from_json/1)}]

  defp decode_json_field(:gamma, value),
    do: [
      {:safrole,
       Safrole.from_json(%{
         pending: value[:gamma_k],
         epoch_root: value[:gamma_z],
         slot_sealers: value[:gamma_s],
         ticket_accumulator: value[:gamma_a]
       })}
    ]

  defp decode_json_field(:gamma_k, value), do: [{:safrole_pending, value}]
  defp decode_json_field(:gamma_z, value), do: [{:safrole_epoch_root, value}]
  defp decode_json_field(:gamma_s, value), do: [{:safrole_slot_sealers, value}]
  defp decode_json_field(:gamma_a, value), do: [{:safrole_ticket_accumulator, value}]
  defp decode_json_field(:psi, value), do: [{:judgements, Judgements.from_json(value)}]

  defp decode_json_field(:pi, value),
    do: [{:validator_statistics, ValidatorStatistics.from_json(value)}]

  defp decode_json_field(:avail_assignments, value), do: decode_json_field(:rho, value)

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
          slot_sealers: fields[:safrole_slot_sealers],
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
