defmodule System.State do
  alias Block.Extrinsic.Assurance
  alias Block.Extrinsic.Guarantee
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Codec.{NilDiscriminator, VariableSize}
  alias Constants
  alias System.State

  alias System.State.{
    CoreReport,
    EntropyPool,
    Judgements,
    PrivilegedServices,
    RecentHistory,
    RotateKeys,
    Safrole,
    ServiceAccount,
    Validator,
    ValidatorStatistics
  }

  @type t :: %__MODULE__{
          # Formula (85) v0.3.4
          authorizer_pool: list(list(Types.hash())),
          recent_history: RecentHistory.t(),
          safrole: Safrole.t(),
          # Formula (88) v0.3.4 # TODO enforce key to be less than 2^32
          # Formula (89) v0.3.4
          services: %{integer() => ServiceAccount.t()},
          entropy_pool: EntropyPool.t(),
          # Formula (52) v0.3.4
          next_validators: list(Validator.t()),
          curr_validators: list(Validator.t()),
          prev_validators: list(Validator.t()),
          core_reports: list(CoreReport.t() | nil),
          timeslot: integer(),
          # Formula (85) v0.3.4
          authorizer_queue: list(list(Types.hash())),
          privileged_services: PrivilegedServices.t(),
          judgements: Judgements.t(),
          validator_statistics: ValidatorStatistics.t()
        }

  # Formula (15) v0.4.0 σ ≡ (α, β, γ, δ, η, ι, κ, λ, ρ, τ, φ, χ, ψ, π)
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
    validator_statistics: %ValidatorStatistics{}
  ]

  # Formula (12) v0.4.0
  @spec add_block(System.State.t(), Block.t()) :: {:error, System.State.t(), <<_::64, _::_*8>>}
  def add_block(%State{} = state, %Block{header: h, extrinsic: e} = block) do
    # Formula (16) v0.4.0
    # Formula (46) v0.4.0
    timeslot_ = h.timeslot

    with :ok <- Block.validate(block, state),
         # β† Formula (17) v0.4.0
         initial_recent_history =
           RecentHistory.update_latest_state_root_(state.recent_history, h),
         # δ† Formula (24) v0.4.0
         services_intermediate =
           State.Services.process_preimages(state.services, e.preimages, timeslot_),
         # ψ' Formula (23) v0.4.0
         {:ok, judgements_, bad_wonky_verdicts} <-
           Judgements.calculate_judgements_(h, e.disputes, state),
         # ρ† Formula (25) v0.4.0
         core_reports_intermediate_1 =
           State.CoreReport.process_disputes(state.core_reports, bad_wonky_verdicts),
         # ρ‡ Formula (26) v0.4.0
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
         # ρ' Formula (27) v0.4.0
         {:ok, core_reports_} <-
           State.CoreReport.calculate_core_reports_(
             core_reports_intermediate_2,
             e.guarantees,
             timeslot_
           ),
         # Formula (28) v0.4.0
         # Formula (29) v0.4.0
         {_services_, _privileged_services, _next_validators_, authorizer_queue_,
          beefy_commitment_map} =
           State.Accumulation.accumulate(
             e.assurances,
             core_reports_,
             services_intermediate,
             state.privileged_services,
             state.next_validators,
             state.authorizer_queue
           ),
         # α' Formula (30) v0.4.0
         authorizer_pool_ =
           calculate_authorizer_pool_(
             e.guarantees,
             authorizer_queue_,
             state.authorizer_pool,
             h.timeslot
           ),
         # β' Formula (18) v0.4.0
         recent_history_ =
           RecentHistory.calculate_recent_history_(
             h,
             e.guarantees,
             initial_recent_history,
             beefy_commitment_map
           ),
         # κ' Formula (21) v0.4.0
         # λ' Formula (22) v0.4.0
         # γ'(gamma_k, gamma_z) Formula (19) v0.4.0
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

         # η' Formula (20) v0.4.0
         rotated_history_entropy_pool =
           EntropyPool.rotate_history(h, state.timeslot, state.entropy_pool),
         :ok <-
           System.Validators.Safrole.valid_epoch_marker(
             h,
             state.timeslot,
             rotated_history_entropy_pool.n1,
             pending_
           ),
         # Formula (69) v0.3.4
         epoch_slot_sealers_ =
           Safrole.get_epoch_slot_sealers_(
             h,
             state.timeslot,
             state.safrole,
             rotated_history_entropy_pool,
             curr_validators_
           ),
         # Formula (79) v0.3.4
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
         # π' Formula (31) v0.4.0
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
         # TODO
         services: nil,
         # η'
         entropy_pool: entropy_pool_,
         # ι'
         # TODO
         next_validators: nil,
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
         # TODO
         privileged_services: nil,
         # ψ'
         judgements: judgements_,
         # π'
         validator_statistics: validator_statistics_
       }}
    else
      {:error, reason} -> {:error, state, reason}
    end
  end

  # Formula (86) v0.3.4
  def calculate_authorizer_pool_(
        guarantees,
        authorizer_queue_,
        authorizer_pools,
        timeslot
      ) do
    # Zip the authorizer pools with the posterior authorizer queue
    # and use the index to keep track of the core index
    Enum.zip(authorizer_pools, authorizer_queue_)
    |> Enum.with_index()
    |> Enum.map(fn {{current_pool, queue}, core_index} ->
      # Adjust the current pool by removing the oldest used authorizer
      adjusted_pool = remove_oldest_used_authorizer(core_index, current_pool, guarantees)

      # Calculate the timeslot index using the header's timeslot
      timeslot_index = rem(timeslot, Constants.max_authorization_queue_items())

      # Pick the correct element from the queue based on the timeslot index
      selected_queue_element = Enum.at(queue, timeslot_index)

      # Add the selected queue element to the adjusted pool
      authorizer_pool_ = adjusted_pool ++ [selected_queue_element]

      # Take only the rightmost elements to ensure the pool size is within the limit
      # Adjust to take only if the pool exceeds the max size
      Enum.take(authorizer_pool_, -Constants.max_authorizations_items())
    end)
  end

  # Formula (87) v0.3.4 F(c)
  # Function to remove the oldest (first from left) used authorizer from the pool
  def remove_oldest_used_authorizer(core_index, current_pool, guarantees) do
    case Enum.find(guarantees, &(&1.work_report.core_index == core_index)) do
      nil ->
        current_pool

      %Guarantee{work_report: %WorkReport{authorizer_hash: hash}} ->
        {left, right} = Enum.split_while(current_pool, &(&1 != hash))
        left ++ tl(right)
    end
  end

  def e(v), do: Codec.Encoder.encode(v)

  # Formula (292) v0.3.4
  def state_keys(s) do
    %{
      # C(1) ↦ E([↕x ∣ x <− α])
      1 => e(s.authorizer_pool |> Enum.map(&VariableSize.new/1)),
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
      10 => e(s.core_reports |> Enum.map(&NilDiscriminator.new/1)),
      # C(11) ↦ E4(τ)
      11 => Codec.Encoder.encode_le(s.timeslot, 4),
      # C(12) ↦ E4(χ)
      12 => Codec.Encoder.encode(s.privileged_services),
      # C(13) ↦ E4(π)
      13 => Codec.Encoder.encode(s.validator_statistics)
    }
    |> encode_accounts(s)
    |> encode_accounts_storage(s, :storage)
    |> encode_accounts_storage(s, :preimage_storage_p)
    |> encode_accounts_preimage_storage_l(s)
  end

  # Formula (291) v0.3.4 - C constructor
  # (i, s ∈ NS) ↦ [i, n0, n1, n2, n3, 0, 0, . . . ] where n = E4(s)
  def key_to_32_octet({i, s}) when i < 256 and s < 4_294_967_296 do
    <<i::8>> <> Codec.Encoder.encode_le(s, 4) <> <<0::216>>
  end

  # (s, h) ↦ [n0, h0, n1, h1, n2, h2, n3, h3, h4, h5, . . . , h27] where
  def key_to_32_octet({s, h}) do
    <<n0, n1, n2, n3>> = Codec.Encoder.encode_le(s, 4)
    <<h_part::binary-size(28), _rest::binary>> = h
    <<h0, h1, h2, h3, rest::binary>> = h_part
    <<n0, h0, n1, h1, n2, h2, n3, h3>> <> rest
  end

  # i ∈ N2^8 ↦ [i, 0, 0, . . . ]
  def key_to_32_octet(key) when key < 256, do: <<key::8, 0::248>>

  def serialize(state) do
    state_keys(state)
    |> Enum.map(fn {k, v} -> {key_to_32_octet(k), v} end)
    |> Enum.into(%{})
  end

  # ∀(s ↦ a) ∈ δ ∶ C(255, s) ↦ ac ⌢ E8(ab, ag, am, al) ⌢ E4(ai) ,
  defp encode_accounts(%{} = state_keys, %State{} = state) do
    state.services
    |> Enum.reduce(state_keys, fn {id, service}, ac ->
      Map.put(ac, {255, id}, Codec.Encoder.encode(service))
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
        value =
          t
          |> Enum.map(&Codec.Encoder.encode_le(&1, 4))
          |> VariableSize.new()
          |> Codec.Encoder.encode()

        <<_::binary-size(4), rest::binary>> = h
        key = Codec.Encoder.encode_le(l, 4) <> Utils.invert_bits(rest)
        Map.put(ac, {s, key}, value)
      end)
    end)
  end

  def from_json(json) do
    %{
      "tau" => timeslot,
      "eta" => entropy_pool,
      "lambda" => prev_validators,
      "kappa" => curr_validators,
      "iota" => next_validators,
      "gamma_k" => pending,
      "gamma_a" => ticket_accumulator,
      "gamma_s" => current_epoch_slot_sealers,
      "gamma_z" => epoch_root
    } = json

    %System.State{
      timeslot: timeslot,
      entropy_pool: EntropyPool.from_json(entropy_pool),
      prev_validators: Enum.map(prev_validators, &Validator.from_json/1),
      curr_validators: Enum.map(curr_validators, &Validator.from_json/1),
      next_validators: Enum.map(next_validators, &Validator.from_json/1),
      safrole:
        Safrole.from_json(%{
          pending: pending,
          epoch_root: epoch_root,
          current_epoch_slot_sealers: current_epoch_slot_sealers,
          ticket_accumulator: ticket_accumulator
        })
    }
  end
end
