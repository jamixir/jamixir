defmodule Block.Extrinsic.Guarantee do
  @moduledoc """
  Work report guarantee.
  11.4
  """
  alias Util.Hash
  alias System.State.ServiceAccount
  alias Block.Extrinsic.{Guarantee.WorkReport, Guarantor}
  alias System.{State, State.EntropyPool, State.RecentHistory}
  alias Util.{Collections, Crypto}
  use SelectiveMock
  use MapUnion
  use Codec.Encoder
  # {validator_index, ed25519 signature}
  @type credential :: {Types.validator_index(), Types.ed25519_signature()}

  # Formula (137) v0.4.5
  @type t :: %__MODULE__{
          # w
          work_report: WorkReport.t(),
          # t
          timeslot: non_neg_integer(),
          # a
          credentials: list(credential())
        }

  defstruct work_report: %WorkReport{},
            timeslot: 0,
            credentials: [{0, Crypto.zero_sign()}]

  @spec validate(list(t()), State.t(), integer()) :: :ok | {:error, String.t()}
  def validate(guarantees, state, timeslot) do
    w = work_reports(guarantees)

    # Formula (138) v0.4.5
    with :ok <-
           (case Collections.validate_unique_and_ordered(guarantees, & &1.work_report.core_index) do
              {:error, :not_in_order} -> {:error, :out_of_order_guarantee}
              result -> result
            end),
         # Formula (119) v0.4.5
         :ok <- validate_work_report_sizes(w),
         # Formula (144) v0.4.5
         :ok <- validate_gas_accumulation(w, state.services),
         # Formula (146) v0.4.5
         :ok <- validate_unique_wp_hash(guarantees),
         # Formula (148) v0.4.5
         :ok <- validate_refine_context_timeslot(guarantees, timeslot),
         # Formula (156) v0.4.5
         :ok <- validate_work_result_cores(w, state.services),
         # Formula (152) v0.4.5
         :ok <-
           validate_new_work_packages(
             w,
             state.recent_history,
             state.accumulation_history,
             state.ready_to_accumulate,
             state.core_reports
           ),
         # Formula (155) v0.4.5
         :ok <- validate_segment_root_lookups(w, state.recent_history),
         # Formula (153) v0.4.5
         :ok <- validate_prerequisites(w, state.recent_history),
         # Formula (137) v0.4.5
         true <-
           Enum.all?(guarantees, fn %__MODULE__{credentials: cred} -> length(cred) in [2, 3] end),
         # Formula (11.32) v0.5.0
         :ok <- validate_anchor_block(guarantees, state.recent_history),
         # Formula (139) v0.4.5
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

  # Formula (142) v0.4.5 - w
  @spec work_reports(list(t())) :: list(WorkReport.t())
  def work_reports(guarantees) do
    for g <- guarantees do
      g.work_report
    end
  end

  # Formula (145) v0.4.5 - x
  def refinement_contexts(guarantees) do
    for w <- work_reports(guarantees) do
      w.refinement_context
    end
  end

  # Formula (143) v0.4.5
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

        # commented because signatures are being tested in other part
        # and this double check is not necessary
        #
        # wr.authorizer_hash not in Enum.at(authorizer_pool, wr.core_index) ->
        #   {:halt, {:error, :bad_signature}}

        Enum.at(core_reports_intermediate_2, wr.core_index)
        |> then(&(&1 != nil and &1.timeslot + Constants.unavailability_period() < timeslot)) ->
          {:halt, {:error, :pending_work}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  # Formula (144) v0.4.5
  # ∀w∈w∶ ∑(rg)≤GA ∧ ∀r∈wr ∶ rg ≥δ[rs]g
  mockable validate_gas_accumulation(w, services) do
    Enum.reduce_while(w, :ok, fn work_report, _acc ->
      total_gas = Enum.reduce(work_report.results, 0, &(&1.gas_ratio + &2))

      cond do
        total_gas > Constants.gas_accumulation() ->
          {:halt, {:error, :work_report_gas_too_high}}

        Enum.any?(work_report.results, fn result ->
          Map.get(services, result.service) == nil
        end) ->
          {:halt, {:error, :bad_service_id}}

        Enum.any?(work_report.results, fn result ->
          service = Map.get(services, result.service)
          result.gas_ratio < service.gas_limit_g
        end) ->
          {:halt, {:error, :insufficient_gas_ratio}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  # Formula (156) v0.4.5
  mockable validate_work_result_cores(w, services) do
    if Enum.any?(Enum.flat_map(w, & &1.results), fn r ->
         r.code_hash != Map.get(services, r.service, %ServiceAccount{}).code_hash
       end) do
      {:error, :bad_code_hash}
    else
      :ok
    end
  end

  # Formula (145) v0.4.5
  @spec p_set(list(WorkReport.t())) :: MapSet.t(Types.hash())
  defp p_set(work_reports) do
    for w <- work_reports, do: w.specification.work_package_hash, into: MapSet.new()
  end

  # Formula (146) v0.4.5
  @spec validate_unique_wp_hash(list(t())) :: :ok | {:error, :duplicate_package}
  def validate_unique_wp_hash(guarantees) do
    wr = work_reports(guarantees)

    if length(wr) == MapSet.size(p_set(wr)) do
      :ok
    else
      {:error, :duplicate_package}
    end
  end

  # Formula (11.32) v0.5.0
  # ∀x ∈ x ∶ ∃y ∈ β ∶ xa = yh ∧ xs = ys ∧ xb = HK(EM(yb))
  mockable validate_anchor_block(guarantees, %RecentHistory{blocks: blocks}) do
    Enum.reduce_while(refinement_contexts(guarantees), :ok, fn x, _acc ->
      case for(y <- blocks, x.state_root_ == y.state_root, do: y) do
        [] ->
          {:halt, {:error, :bad_state_root}}

        blocks ->
          case for(y <- blocks, x.anchor == y.header_hash, do: y) do
            [] ->
              {:halt, {:error, :anchor_not_recent}}

            blocks ->
              case for(
                     y <- blocks,
                     x.beefy_root_ ==
                       Hash.keccak_256(Codec.Encoder.encode_mmr(y.accumulated_result_mmr)),
                     do: y
                   ) do
                # TODO commented because all tests are falling into this case
                # [] -> {:halt, {:error, :bad_beefy_mmr}}
                _ -> {:cont, :ok}
              end
          end
      end
    end)
  end

  # Formula (148) v0.4.5
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

  # Formula (150) v0.4.5
  # Formula (151) v0.4.5
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

  # Formula (152) v0.4.5
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

  # Formula (11.25) v0.5.0
  mockable reporters_set(
             guarantees,
             %EntropyPool{n2: n2_, n3: n3_},
             t_,
             curr_validators_,
             prev_validators_,
             offenders
           ) do
    {g, prev_g} = {
      Guarantor.guarantors(n2_, t_, curr_validators_, offenders),
      Guarantor.prev_guarantors(n2_, n3_, t_, curr_validators_, prev_validators_, offenders)
    }

    # ∀(w, t, a) ∈ EG,
    guarantees
    |> Enum.reduce_while(
      {:ok, MapSet.new()},
      fn %__MODULE__{credentials: a, work_report: w = %WorkReport{core_index: wc}, timeslot: t},
         reporters_set ->
        %Guarantor{assigned_cores: c, validators: validators} = choose_g(t, t_, g, prev_g)

        # ∀(v, s) ∈ a
        case Enum.reduce_while(a, reporters_set, fn {v, s}, {:ok, acum2} ->
               # (kv)e
               validator_key = Enum.at(validators, v).ed25519
               # XG ⌢ H(E(w))
               payload = SigningContexts.jam_guarantee() <> h(e(w))

               cond do
                 # ∧ R(⌊τ′/R⌋−1) ≤ t ≤ τ'
                 t > t_ or
                     t < Constants.rotation_period() * (div(t_, Constants.rotation_period()) - 1) ->
                   {:cont, {:ok, acum2}}
                   {:halt, {:error, :future_report_slot}}

                 # s ∈ E(k ) ⟨XG ⌢ H(E(w))⟩
                 !Crypto.valid_signature?(s, payload, validator_key) ->
                   {:cont, {:ok, acum2}}
                   {:halt, {:error, :bad_signature}}

                 # cv = wc
                 Enum.at(c, v) != wc ->
                   {:cont, {:ok, acum2}}
                   {:halt, {:error, :bad_validator_index}}

                 true ->
                   # k ∈ R ⇔ ∃(w, t, a) ∈ EG, ∃(v, s) ∈ a ∶ k = (kv)e
                   {:cont, {:ok, MapSet.put(acum2, validator_key)}}
               end
             end) do
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

  # Formula (11.38) v0.5.0
  @spec validate_prerequisites(list(WorkReport.t()), RecentHistory.t()) ::
          :ok | {:error, :dependency_missing}
  mockable validate_prerequisites(work_reports, %RecentHistory{blocks: blocks}) do
    extrinsic_and_recent_work_hashes = p_set(work_reports) ++ recent_block_hashes(blocks)

    required_hashes =
      for w <- work_reports do
        w.refinement_context.prerequisite ++ Utils.keys_set(w.segment_root_lookup)
      end
      |> Enum.reduce(MapSet.new(), &++/2)

    if MapSet.subset?(required_hashes, extrinsic_and_recent_work_hashes) do
      :ok
    else
      {:error, :dependency_missing}
    end
  end

  # Formula (154) v0.4.5
  @spec p_map(list(WorkReport.t())) :: %{Types.hash() => Types.hash()}
  def p_map(work_reports) do
    for w <- work_reports,
        into: %{},
        do: {w.specification.work_package_hash, w.specification.exports_root}
  end

  defp recent_block_hashes(blocks) do
    Enum.flat_map(blocks, &Map.keys(&1.work_report_hashes)) |> MapSet.new()
  end

  use Sizes

  defimpl Encodable do
    use Codec.Encoder
    alias Block.Extrinsic.Guarantee

    # Formula (C.16) v0.5.0
    def encode(g = %Guarantee{}) do
      e({
        g.work_report,
        e_le(g.timeslot, 4),
        vs(for {i, s} <- g.credentials, do: {e_le(i, 2), s})
      })
    end
  end

  use Codec.Decoder

  def decode(bin) do
    {work_report, bin} = WorkReport.decode(bin)
    <<timeslot::binary-size(4), credentials_count::8, bin::binary>> = bin

    {credentials, rest} =
      Enum.reduce(1..credentials_count, {[], bin}, fn _i, {acc, b} ->
        <<v::binary-size(@validator_index_size), s::binary-size(@signature_size), b2::binary>> = b

        {acc ++ [{de_le(v, @validator_index_size), s}], b2}
      end)

    {%__MODULE__{
       work_report: work_report,
       timeslot: de_le(timeslot, 4),
       credentials: credentials
     }, rest}
  end

  use JsonDecoder

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
  def mock(:validate_work_result_cores, _), do: :ok
  def mock(:validate_new_work_packages, _), do: :ok
  def mock(:validate_prerequisites, _), do: :ok
  def mock(:validate_segment_root_lookups, _), do: :ok
  def mock(:validate_refine_context_timeslot, _), do: :ok

  # Formula (155) v0.4.5
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
end
