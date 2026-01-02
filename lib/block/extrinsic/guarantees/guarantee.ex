defmodule Block.Extrinsic.Guarantee do
  alias Codec.VariableSize
  alias Block.Extrinsic.{Guarantee.WorkReport, GuarantorAssignments}
  alias Block.Header
  alias System.{State, State.EntropyPool, State.RecentHistory, State.ServiceAccount}
  alias Util.{Collections, Crypto}
  use SelectiveMock
  use MapUnion
  use JsonDecoder
  import Codec.Encoder
  use Sizes
  # {validator_index, ed25519 signature}
  @type credential :: {Types.validator_index(), Types.ed25519_signature()}

  # Formula (11.23) v0.7.2
  @type t :: %__MODULE__{
          # r
          work_report: WorkReport.t(),
          # t
          timeslot: non_neg_integer(),
          # a
          credentials: list(credential())
        }

  defstruct work_report: %WorkReport{},
            timeslot: 0,
            credentials: [{0, Crypto.zero_sign()}]

  @spec validate(list(t()), State.t(), Header.t()) :: :ok | {:error, String.t()}
  mockable validate(guarantees, state, %Header{timeslot: t, prior_state_root: s}) do
    w = work_reports(guarantees)

    # Formula (11.24) v0.7.2
    with :ok <-
           (case Collections.validate_unique_and_ordered(guarantees, & &1.work_report.core_index) do
              {:error, :not_in_order} -> {:error, :out_of_order_guarantee}
              result -> result
            end),
         # Formula (11.3) v0.7.2
         :ok <- validate_work_report_sizes(w),
         # Formula (11.30) v0.7.2
         :ok <- validate_gas_accumulation(w, state.services),
         # Formula (11.32) v0.7.2
         :ok <- validate_unique_wp_hash(guarantees),
         # Formula (11.34) v0.7.2
         :ok <- validate_refine_context_timeslot(guarantees, t),
         # Formula (11.42) v0.7.2
         :ok <- validate_work_digest_cores(w, state.services),
         # Formula (11.38) v0.7.2
         :ok <-
           validate_new_work_packages(
             w,
             state.recent_history,
             state.accumulation_history,
             state.ready_to_accumulate,
             state.core_reports
           ),
         # Formula (11.41) v0.7.2
         :ok <- validate_segment_root_lookups(w, state.recent_history),
         # Formula (11.39) v0.7.2
         :ok <- validate_prerequisites(w, state.recent_history),
         # Formula (11.23) v0.7.2
         true <-
           Enum.all?(guarantees, fn
             %__MODULE__{credentials: [_, _]} -> true
             %__MODULE__{credentials: [_, _, _]} -> true
             _ -> false
           end),
         # Formula (11.33) v0.7.2
         :ok <- validate_anchor_block(guarantees, state.recent_history, s),
         # Formula (11.25) v0.7.2
         :ok <-
           if(
             Collections.all_ok?(guarantees, fn %__MODULE__{credentials: cred} ->
               Collections.validate_unique_and_ordered(cred, &elem(&1, 0))
             end),
             do: :ok,
             else: {:error, :not_sorted_or_unique_guarantors}
           ) do
      :ok
    else
      {:error, error} -> {:error, error}
      false -> {:error, :insufficient_guarantees}
    end
  end

  @spec validate_work_report_sizes(list(WorkReport.t())) :: :ok | {:error, String.t()}
  defp validate_work_report_sizes(work_reports) do
    if Enum.all?(work_reports, &WorkReport.valid_size?/1) do
      :ok
    else
      {:error, :too_many_dependencies}
    end
  end

  # Formula (11.28) v0.7.2 - I
  @spec work_reports(list(t())) :: list(WorkReport.t())
  def work_reports(guarantees), do: for(g <- guarantees, do: g.work_report)

  # Formula (11.31) v0.7.2 - x
  def refinement_contexts(guarantees),
    do: for(r <- work_reports(guarantees), do: r.refinement_context)

  # Formula (11.29) v0.7.2
  mockable validate_availability(
             guarantees,
             core_reports_intermediate_2,
             timeslot,
             authorizer_pool
           ) do
    Enum.reduce_while(work_reports(guarantees), :ok, fn wr, _ ->
      cond do
        wr.core_index > Constants.core_count() - 1 ->
          {:halt, {:error, :bad_core_index}}

        wr.authorizer_hash not in Enum.at(authorizer_pool, wr.core_index) ->
          {:halt, {:error, :core_unauthorized}}

        Enum.at(core_reports_intermediate_2, wr.core_index)
        |> then(&(&1 != nil and &1.timeslot + Constants.unavailability_period() > timeslot)) ->
          {:halt, {:error, :core_engaged}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  # Formula (11.30) v0.7.2
  # ∀r ∈ I∶ ∑(d_g)≤GA ∧ ∀d∈r_d ∶ d_g ≥ δ[d_s]_g
  mockable validate_gas_accumulation(w, services) do
    Enum.reduce_while(w, :ok, fn work_report, _acc ->
      total_gas = Enum.reduce(work_report.digests, 0, &(&1.gas_ratio + &2))

      cond do
        total_gas > Constants.gas_accumulation() ->
          {:halt, {:error, :work_report_gas_too_high}}

        Enum.any?(work_report.digests, fn digest ->
          Map.get(services, digest.service) == nil
        end) ->
          {:halt, {:error, :bad_service_id}}

        Enum.any?(work_report.digests, fn digest ->
          service = Map.get(services, digest.service)
          digest.gas_ratio < service.gas_limit_g
        end) ->
          {:halt, {:error, :insufficient_gas_ratio}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  # Formula (11.42) v0.7.2
  mockable validate_work_digest_cores(w, services) do
    if Enum.any?(Enum.flat_map(w, & &1.digests), fn digest ->
         digest.code_hash != Map.get(services, digest.service, %ServiceAccount{}).code_hash
       end) do
      {:error, :bad_code_hash}
    else
      :ok
    end
  end

  # Formula (11.31) v0.7.2
  # p ≡ {(rs)p ∣ r ∈ I}
  @spec p_set(list(WorkReport.t())) :: MapSet.t(Types.hash())
  defp p_set(work_reports) do
    for r <- work_reports, do: r.specification.work_package_hash, into: MapSet.new()
  end

  # Formula (11.32) v0.7.2
  # |p| = |I|
  @spec validate_unique_wp_hash(list(t())) :: :ok | {:error, :duplicate_package}
  def validate_unique_wp_hash(guarantees) do
    wr = work_reports(guarantees)

    if length(wr) == MapSet.size(p_set(wr)) do
      :ok
    else
      {:error, :duplicate_package}
    end
  end

  # Formula (11.33) v0.7.2
  # ∀x ∈ x ∶ ∃y ∈ β†H ∶ xa = yh ∧ xs = ys ∧ xb = yb
  mockable validate_anchor_block(guarantees, %RecentHistory{} = beta, prior_state_root) do
    beta_dagger = RecentHistory.update_latest_state_root(beta, prior_state_root)

    Enum.reduce_while(refinement_contexts(guarantees), :ok, fn x, _acc ->
      # xs = ys
      case for(y <- beta_dagger.blocks, x.state_root == y.state_root, do: y) do
        [] ->
          {:halt, {:error, :bad_state_root}}

        blocks ->
          # xa = yh
          case for(y <- blocks, x.anchor == y.header_hash, do: y) do
            [] ->
              {:halt, {:error, :anchor_not_recent}}

            blocks ->
              # xb = yb
              case for(
                     y <- blocks,
                     x.beefy_root ==
                       y.beefy_root,
                     do: y
                   ) do
                [] -> {:halt, {:error, :bad_beefy_mmb}}
                _ -> {:cont, :ok}
              end
          end
      end
    end)
  end

  # Formula (11.34) v0.7.2
  mockable validate_refine_context_timeslot(guarantees, t) do
    if Enum.all?(
         refinement_contexts(guarantees),
         &(&1.timeslot >= t - Constants.max_age_lookup_anchor())
       ) do
      :ok
    else
      {:error, :refine_context_timeslot}
    end
  end

  # Formula (11.36) v0.7.2
  # Formula (11.37) v0.7.2
  @spec collect_prerequisites(
          list(%{work_report: WorkReport.t()})
          | list(list(%{work_report: WorkReport.t()}))
        ) :: MapSet.t(Types.hash())
  def collect_prerequisites(items) do
    for item <- List.flatten(items),
        item != nil,
        reduce: MapSet.new() do
      acc -> acc ++ item.work_report.refinement_context.prerequisite
    end
  end

  # Formula (11.38) v0.7.2
  mockable validate_new_work_packages(
             work_reports,
             %RecentHistory{blocks: blocks},
             accumulation_history,
             ready_to_accumulate,
             core_reports
           ) do
    accumulated = Enum.reduce(accumulation_history, MapSet.new(), &(&1 ++ &2))

    existing_packages =
      recent_block_hashes(blocks) ++
        accumulated ++
        collect_prerequisites(ready_to_accumulate) ++
        collect_prerequisites(core_reports)

    if MapSet.disjoint?(p_set(work_reports), existing_packages) do
      :ok
    else
      {:error, :duplicate_package}
    end
  end

  # Formula (11.26) v0.7.2
  mockable reporters_set(
             guarantees,
             %EntropyPool{n2: n2_, n3: n3_},
             t_,
             curr_validators_,
             prev_validators_,
             offenders
           ) do
    {g, prev_g} = {
      GuarantorAssignments.guarantors(n2_, t_, curr_validators_, offenders),
      GuarantorAssignments.prev_guarantors(
        n2_,
        n3_,
        t_,
        curr_validators_,
        prev_validators_,
        offenders
      )
    }

    # ∀(r, t, a) ∈ EG,
    guarantees
    |> Enum.reduce_while(
      {:ok, MapSet.new()},
      fn %__MODULE__{credentials: a, work_report: r = %WorkReport{core_index: rc}, timeslot: t},
         reporters_set ->
        %GuarantorAssignments{assigned_cores: c, validators: validators} =
          choose_g(t, t_, g, prev_g)

        # ∀(v, s) ∈ a
        result =
          Enum.reduce_while(a, reporters_set, fn {v, s}, {:ok, acum2} ->
            case Enum.at(validators, v) do
              nil ->
                {:halt, {:error, :bad_validator_index}}

              validator ->
                # (kv)e
                validator_key = validator.ed25519
                # XG ⌢ H(r)
                payload = SigningContexts.jam_guarantee() <> h(e(r))

                cond do
                  # ∧ R(⌊τ′/R⌋−1) ≤ t ≤ τ'
                  t > t_ or
                      t <
                        Constants.rotation_period() *
                          (div(t_, Constants.rotation_period()) - 1) ->
                    {:halt, {:error, :future_report_slot}}

                  # s ∈ V(kv)e ⟨X_G ⌢ H(r)⟩
                  !Crypto.valid_signature?(s, payload, validator_key) ->
                    {:halt, {:error, :bad_signature}}

                  # c_v = r_c
                  Enum.at(c, v) != rc ->
                    {:halt, {:error, :wrong_assignment}}

                  true ->
                    # k ∈ R ⇔ ∃(w, t, a) ∈ EG, ∃(v, s) ∈ a ∶ k = (kv)e
                    {:cont, {:ok, MapSet.put(acum2, validator_key)}}
                end
            end
          end)

        case result do
          {:ok, updated_keys} ->
            {:cont, {:ok, updated_keys}}

          {:error, msg} ->
            {:halt, {:error, msg}}
        end
      end
    )
  end

  def choose_g(t, t_, g, prev_g) do
    if div(t_, Constants.rotation_period()) == div(t, Constants.rotation_period()) do
      g
    else
      prev_g
    end
  end

  # Formula (11.39) v0.7.2
  @spec validate_prerequisites(list(WorkReport.t()), RecentHistory.t()) ::
          :ok | {:error, :dependency_missing}
  mockable validate_prerequisites(work_reports, %RecentHistory{blocks: blocks}) do
    extrinsic_and_recent_work_hashes = p_set(work_reports) ++ recent_block_hashes(blocks)

    required_hashes =
      for r <- work_reports do
        r.refinement_context.prerequisite ++ Utils.keys_set(r.segment_root_lookup)
      end
      |> Enum.reduce(MapSet.new(), &++/2)

    if MapSet.subset?(required_hashes, extrinsic_and_recent_work_hashes) do
      :ok
    else
      {:error, :dependency_missing}
    end
  end

  # Formula (11.40) v0.7.2
  @spec p_map(list(WorkReport.t())) :: %{Types.hash() => Types.hash()}
  def p_map(work_reports) do
    for r <- work_reports,
        into: %{},
        do: {r.specification.work_package_hash, r.specification.exports_root}
  end

  defp recent_block_hashes(blocks) do
    Enum.flat_map(blocks, &Map.keys(&1.work_report_hashes)) |> MapSet.new()
  end

  defimpl Encodable do
    import Codec.Encoder
    alias Block.Extrinsic.Guarantee

    # Formula (C.19) v0.7.2
    def encode(%Guarantee{timeslot: timeslot} = g) do
      e({
        g.work_report,
        t(timeslot),
        Guarantee.encode_credentials(g.credentials)
      })
    end
  end

  def encode_credentials(creds) do
    e(vs(for {validator_index, s} <- creds, do: {t(validator_index), s}))
  end

  def decode_credentials(bin) do
    {credentials, _rest} =
      VariableSize.decode(bin, fn b ->
        <<v::m(validator_index), s::binary-size(@signature_size), rest::binary>> = b
        {{v, s}, rest}
      end)

    credentials
  end

  def decode(bin) do
    {work_report, bin} = WorkReport.decode(bin)
    <<timeslot::m(timeslot), bin::binary>> = bin

    {credentials, rest} =
      VariableSize.decode(bin, fn b ->
        <<v::m(validator_index), s::binary-size(@signature_size), rest::binary>> = b
        {{v, s}, rest}
      end)

    {%__MODULE__{work_report: work_report, timeslot: timeslot, credentials: credentials}, rest}
  end

  def json_mapping,
    do: %{
      work_report: %{m: WorkReport, f: :report},
      timeslot: :slot,
      credentials: [&json_credentials/1, :signatures]
    }

  def json_credentials(json) do
    for c <- json, do: {c.validator_index, JsonDecoder.from_json(c.signature)}
  end

  def mock(:validate_availability, _), do: :ok
  def mock(:reporters_set, _), do: {:ok, MapSet.new()}
  def mock(:validate_anchor_block, _), do: :ok
  def mock(:validate_gas_accumulation, _), do: :ok
  def mock(:validate_work_digest_cores, _), do: :ok
  def mock(:validate_new_work_packages, _), do: :ok
  def mock(:validate_prerequisites, _), do: :ok
  def mock(:validate_segment_root_lookups, _), do: :ok
  def mock(:validate_refine_context_timeslot, _), do: :ok
  def mock(:validate, _), do: :ok

  # Formula (11.41) v0.7.2
  @spec validate_segment_root_lookups(list(WorkReport.t()), RecentHistory.t()) ::
          :ok | {:error, String.t()}
  mockable validate_segment_root_lookups(work_reports, %RecentHistory{blocks: blocks}) do
    if Enum.all?(work_reports, fn w ->
         map_subset?(
           w.segment_root_lookup,
           p_map(work_reports) ++ Collections.union(for b <- blocks, do: b.work_report_hashes)
         )
       end) do
      :ok
    else
      {:error, :segment_root_lookup_invalid}
    end
  end

  def map_subset?(map1, map2) do
    Enum.all?(map1, fn {k, v} -> Map.get(map2, k) == v end)
  end

  defp normalize_credentials(credentials) do
    case credentials do
      [_, _] ->
        Enum.sort_by(credentials, &elem(&1, 0)) |> uniq_by_index()

      [_, _, _] ->
        Enum.sort_by(credentials, &elem(&1, 0)) |> uniq_by_index()

      _ ->
        nil
    end
  end

  defp uniq_by_index(creds) do
    if length(creds) == length(Enum.uniq_by(creds, &elem(&1, 0))) do
      creds
    else
      nil
    end
  end

  def guarantees_for_new_block(guarantees, state, next_block_timeslot, latest_state_root) do

    normalized_guarantees =
      guarantees
      |> Enum.map(fn g -> %{g | credentials: normalize_credentials(g.credentials)} end)

    # Apply permanent rejections - these guarantees will be marked as rejected
    {valid_guarantees, rejected_guarantees} =
      Enum.split_with(normalized_guarantees, fn g ->
        not is_nil(g.credentials) and
          validate_work_report_sizes([g.work_report]) == :ok and
          validate_gas_accumulation([g.work_report], state.services) == :ok and
          validate_work_digest_cores([g.work_report], state.services) == :ok
      end)

    # Apply temporary filters - these guarantees are just filtered out but not rejected
    filtered_guarantees =
      Enum.filter(valid_guarantees, fn g ->
        with :ok <- validate_refine_context_timeslot([g], next_block_timeslot),
             :ok <-
               validate_new_work_packages(
                 [g.work_report],
                 state.recent_history,
                 state.accumulation_history,
                 state.ready_to_accumulate,
                 state.core_reports
               ),
             :ok <- validate_segment_root_lookups([g.work_report], state.recent_history),
             :ok <- validate_prerequisites([g.work_report], state.recent_history),
             :ok <- validate_anchor_block([g], state.recent_history, latest_state_root),
             # Formula (11.29) - validate core is available
             :ok <-
               validate_availability(
                 [g],
                 state.core_reports,
                 next_block_timeslot,
                 state.authorizer_pool
               ) do
          true
        else
          _ -> false
        end
      end)

    {filtered_guarantees, rejected_guarantees}
  end
end
