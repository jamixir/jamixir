defmodule System.State do
  alias Block.Extrinsic.Guarantee
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Codec.NilDiscriminator
  alias Codec.VariableSize
  alias Constants

  alias System.State

  alias System.State.{
    Validator,
    Judgements,
    Safrole,
    RecentHistory,
    EntropyPool,
    RotateKeys,
    ServiceAccount,
    CoreReports,
    PrivilegedServices,
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
          core_reports: CoreReports.t(),
          timeslot: integer(),
          # Formula (85) v0.3.4
          authorizer_queue: list(list(Types.hash())),
          privileged_services: PrivilegedServices.t(),
          judgements: Judgements.t(),
          validator_statistics: ValidatorStatistics.t()
        }

  # Formula (15) v0.3.4 σ ≡ (α, β, γ, δ, η, ι, κ, λ, ρ, τ, φ, χ, ψ, π)
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
    core_reports: %CoreReports{},
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

  # Formula (12) v0.3.4
  @spec add_block(State.t(), Block.t()) :: State.t()
  def add_block(%State{} = state, %Block{header: h, extrinsic: e}) do
    # Formula (16) v0.3.4
    # Formula (46) v0.3.4
    new_timeslot = h.timeslot
    # β† Formula (17) v0.3.4
    inital_recent_history =
      RecentHistory.update_latest_posterior_state_root(state.recent_history, h)

    # δ† Formula (24) v0.3.4
    # The post-preimage integration, pre-accumulation intermediate state
    services_intermediate =
      State.Services.process_preimages(state.services, Map.get(e, :preimages), new_timeslot)

    # ρ† Formula (25) v0.3.4
    # post-judgement, pre-assurances-extrinsic intermediate state
    core_reports_intermediate_1 =
      State.CoreReports.process_disputes(state.core_reports, Map.get(e, :disputes))

    # ρ‡ Formula (26) v0.3.4
    # The post-assurances-extrinsic, pre-guarantees-extrinsic, intermediate state
    core_reports_intermediate_2 =
      State.CoreReports.process_availability(
        core_reports_intermediate_1,
        Map.get(e, :availability)
      )

    sorted_guarantees =
      Block.Extrinsic.unique_sorted_guarantees(e)

    # ρ' Formula (27) v0.3.4
    new_core_reports =
      State.CoreReports.posterior_core_reports(
        core_reports_intermediate_2,
        sorted_guarantees,
        state.curr_validators,
        new_timeslot
      )

    # Formula (28) v0.3.4
    {_new_services, _privileged_services, _new_next_validators, new_authorizer_queue,
     beefy_commitment_map} =
      State.Accumulation.accumulate(
        Map.get(e, :availability),
        new_core_reports,
        services_intermediate,
        state.privileged_services,
        state.next_validators,
        state.authorizer_queue
      )

    # α' Formula (29) v0.3.4
    new_authorizer_pool =
      posterior_authorizer_pool(
        sorted_guarantees,
        new_authorizer_queue,
        state.authorizer_pool,
        h.timeslot
      )

    # β' Formula (18) v0.3.4
    new_recent_history =
      RecentHistory.posterior_recent_history(
        h,
        sorted_guarantees,
        inital_recent_history,
        beefy_commitment_map
      )

    # ψ' Formula (23) v0.3.4
    new_judgements =
      Judgements.posterior_judgements(h, Map.get(e, :disputes), state)

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

    # η' Formula (20) v0.3.4
    rotated_history_entropy_pool =
      EntropyPool.rotate_history(h, state.timeslot, state.entropy_pool)

    posterior_epoch_slot_sealers =
      Safrole.get_posterior_epoch_slot_sealers(
        h,
        state.timeslot,
        state.safrole,
        rotated_history_entropy_pool,
        new_curr_validators
      )

    {:ok, %{vrf_signature_output: vrf_output}} =
      System.HeaderSeal.validate_header_seals(
        h,
        new_curr_validators,
        posterior_epoch_slot_sealers,
        state.entropy_pool
      )
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> throw({:error, reason})
      end

    posterior_entropy_pool =
      EntropyPool.update_current_history(vrf_output, rotated_history_entropy_pool)

    new_safrole = %{
      state.safrole
      | pending: new_safrole_pending,
        epoch_root: new_safrole_epoch_root,
        current_epoch_slot_sealers: posterior_epoch_slot_sealers
    }

    %System.State{
      # α'
      authorizer_pool: new_authorizer_pool,
      # β'
      recent_history: new_recent_history,
      # γ'
      safrole: new_safrole,
      # δ'
      # TODO
      services: nil,
      # η'
      entropy_pool: posterior_entropy_pool,
      # ι'
      # TODO
      next_validators: nil,
      # κ'
      curr_validators: new_curr_validators,
      # λ'
      prev_validators: new_prev_validators,
      # ρ'
      # TODO
      core_reports: nil,
      # τ'
      timeslot: new_timeslot,
      # φ'
      authorizer_queue: new_authorizer_queue,
      # χ'
      # TODO
      privileged_services: nil,
      # ψ'
      judgements: new_judgements,
      # π' Formula (30) v0.3.4
      # π' ≺ (EG,EP,EA, ET,τ,κ',H) # https://github.com/gavofyork/graypaper/pull/69
      validator_statistics:
        Application.get_env(:jamixir, :validator_statistics, ValidatorStatistics).posterior_validator_statistics(
          e,
          state.timeslot,
          state.validator_statistics,
          new_curr_validators,
          h
        )
    }
  end

  # Formula (86) v0.3.4
  def posterior_authorizer_pool(
        guarantees,
        posterior_authorizer_queue,
        authorizer_pools,
        timeslot
      ) do
    # Zip the authorizer pools with the posterior authorizer queue
    # and use the index to keep track of the core index
    Enum.zip(authorizer_pools, posterior_authorizer_queue)
    |> Enum.with_index()
    |> Enum.map(fn {{current_pool, queue}, core_index} ->
      # Adjust the current pool by removing the oldest used authorizer
      adjusted_pool = remove_oldest_used_authorizer(core_index, current_pool, guarantees)

      # Calculate the timeslot index using the header's timeslot
      timeslot_index = rem(timeslot, Constants.max_authorization_queue_items())

      # Pick the correct element from the queue based on the timeslot index
      selected_queue_element = Enum.at(queue, timeslot_index)

      # Add the selected queue element to the adjusted pool
      new_authorizer_pool = adjusted_pool ++ [selected_queue_element]

      # Take only the rightmost elements to ensure the pool size is within the limit
      # Adjust to take only if the pool exceeds the max size
      Enum.take(new_authorizer_pool, -Constants.max_authorizations_items())
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
      10 => e(s.core_reports.reports |> Enum.map(&NilDiscriminator.new/1)),
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
        key = Codec.Encoder.encode_le(l, 4) <> rest
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
      "gamma_s" => %{"keys" => current_epoch_slot_sealers},
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
