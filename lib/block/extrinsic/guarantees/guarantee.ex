defmodule Block.Extrinsic.Guarantee do
  @moduledoc """
  Work report guarantee.
  11.4
  """
  alias System.State.ServiceAccount
  alias Block.Extrinsic.{Guarantee.WorkReport, Guarantor}
  alias System.{State, State.EntropyPool, State.RecentHistory}
  alias Util.{Collections, Crypto, Hash}
  use SelectiveMock
  use MapUnion
  # {validator_index, ed25519 signature}
  @type credential :: {Types.validator_index(), Types.ed25519_signature()}

  # Formula (137) v0.4.1
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

    # Formula (138) v0.4.1
    with :ok <- Collections.validate_unique_and_ordered(guarantees, & &1.work_report.core_index),
         # Formula (119) v0.4.1 (moved from CoreReport)
         :ok <- validate_work_report_sizes(w),
         # Formula (144) v0.4.1
         :ok <- validate_gas_accumulation(w, state.services),
         # Formula (146) v0.4.1
         :ok <- validate_unique_wp_hash(guarantees),
         # Formula (148) v0.4.1
         :ok <- validate_refine_context_timeslot(guarantees, timeslot),
         # Formula (152) v0.4.1
         :ok <- validate_work_result_cores(w, state.services),
         # Formula (137) v0.4.1
         true <-
           Enum.all?(guarantees, fn %__MODULE__{credentials: cred} -> length(cred) in [2, 3] end),
         # Formula (139) v0.4.1
         true <-
           Collections.all_ok?(guarantees, fn %__MODULE__{credentials: cred} ->
             Collections.validate_unique_and_ordered(cred, &elem(&1, 0))
           end),
         # Formula (147) v0.4.1
         :ok <- validate_anchor_block(guarantees, state.recent_history) do
      :ok
    else
      {:error, error} -> {:error, error}
      false -> {:error, "Invalid credentials in guarantees"}
    end
  end

  @spec validate_work_report_sizes(list(WorkReport.t())) :: :ok | {:error, String.t()}
  defp validate_work_report_sizes(work_reports) do
    if Enum.all?(work_reports, &WorkReport.valid_size?/1) do
      :ok
    else
      {:error, "Invalid work report size"}
    end
  end

  # Formula (142) v0.4.1 - w
  def work_reports(guarantees) do
    for g <- guarantees do
      g.work_report
    end
  end

  # Formula (145) v0.4.1 - x
  def refinement_contexts(guarantees) do
    for w <- work_reports(guarantees) do
      w.refinement_context
    end
  end

  # Formula (143) v0.4.1
  mockable validate_availability(
             guarantees,
             core_reports_intermediate_2,
             timeslot,
             authorizer_pool
           ) do
    Enum.reduce_while(work_reports(guarantees), :ok, fn wr, _ ->
      cond do
        wr.authorizer_hash not in Enum.at(authorizer_pool, wr.core_index) ->
          {:halt, {:error, :missing_authorizer}}

        Enum.at(core_reports_intermediate_2, wr.core_index)
        |> then(&(&1 != nil and &1.timeslot + Constants.unavailability_period() < timeslot)) ->
          {:halt, {:error, :pending_work}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  def mock(:validate_availability, _), do: :ok
  def mock(:reporters_set, _), do: {:ok, MapSet.new()}
  def mock(:validate_anchor_block, _), do: :ok
  def mock(:validate_gas_accumulation, _), do: :ok
  def mock(:validate_work_result_cores, _), do: :ok
  # Formula (144) v0.4.1
  # ∀w∈w∶ ∑(rg)≤GA ∧ ∀r∈wr ∶ rg ≥δ[rs]g
  mockable validate_gas_accumulation(w, services) do
    Enum.reduce_while(w, :ok, fn work_report, _acc ->
      total_gas = Enum.reduce(work_report.results, 0, &(&1.gas_ratio + &2))

      cond do
        total_gas > Constants.gas_accumulation() ->
          {:halt, {:error, :invalid_gas_accumulation}}

        Enum.any?(work_report.results, fn result ->
          Map.get(services, result.service) == nil
        end) ->
          {:halt, {:error, :non_existent_service}}

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

  # Formula (152) v0.4.1
  mockable validate_work_result_cores(w, services) do
    if Enum.any?(Enum.flat_map(w, & &1.results), fn r ->
         r.code_hash != Map.get(services, r.service, %ServiceAccount{}).code_hash
       end) do
      {:error, :invalid_work_result_core_index}
    else
      :ok
    end
  end

  # Formula (145) v0.4.1
  defp p_set(work_reports) do
    for w <- work_reports, do: w.specification.work_package_hash, into: MapSet.new()
  end

  # Formula (146) v0.4.1
  @spec validate_unique_wp_hash(list(t())) :: :ok | {:error, :duplicated_wp_hash}
  def validate_unique_wp_hash(guarantees) do
    wr = work_reports(guarantees)

    if length(wr) == MapSet.size(p_set(wr)) do
      :ok
    else
      {:error, :duplicated_wp_hash}
    end
  end

  mockable validate_anchor_block(guarantees, %RecentHistory{blocks: blocks}) do
    w = work_reports(guarantees)
    all_work_report_hashes = Enum.flat_map(blocks, & &1.work_report_hashes) |> MapSet.new()

    cond do
      # Formula (147) v0.4.1
      # ∀x ∈ x ∶ ∃y ∈ β ∶ xa = yh ∧ xs = ys ∧ xb = HK(EM(yb))
      !Enum.all?(refinement_contexts(guarantees), fn x ->
        Enum.any?(blocks, fn y ->
          x.anchor == y.header_hash and
            x.state_root_ == y.state_root and
              x.beefy_root_ == Hash.keccak_256(Codec.Encoder.encode_mmr(y.accumulated_result_mmr))
        end)
      end) ->
        {:error, :invalid_anchor_block}

      # Formula (150) v0.4.1
      # ∀p ∈ p,∀x ∈ β ∶ p ∈/ xp
      Enum.any?(p_set(w), &(&1 in all_work_report_hashes)) ->
        {:error, :work_package_in_recent_history}

      # Formula (151) v0.4.1
      # ∀w ∈ w, (wx)p ≠ ∅ ∶ (wx)p ∈ p ∪ {x ∣ x ∈ bp, b ∈ β}
      for(w <- refinement_contexts(guarantees), w.prerequisite != nil, do: w.prerequisite)
      |> Enum.any?(&(&1 not in (p_set(w) ++ all_work_report_hashes))) ->
        {:error, :invalid_prerequisite}

      true ->
        :ok
    end
  end

  # Formula (148) v0.4.1
  def validate_refine_context_timeslot(guarantees, t) do
    if Enum.all?(
         refinement_contexts(guarantees),
         &(&1.timeslot >= t - Constants.max_age_lookup_anchor())
       ) do
      :ok
    else
      {:error, :refine_context_timeslot}
    end
  end

  # Formula (140) v0.4.1
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
               payload = SigningContexts.jam_guarantee() <> Hash.default(Codec.Encoder.encode(w))

               cond do
                 # s ∈ E(k ) ⟨XG ⌢ H(E(w))⟩
                 !Crypto.valid_signature?(s, payload, validator_key) ->
                   {:halt, {:error, "Invalid signature in guarantee"}}

                 # cv = wc
                 Enum.at(c, v) != wc ->
                   {:halt, {:error, "Invalid core_index in guarantee"}}

                 # ∧ R(⌊τ′/R⌋−1) ≤ t ≤ τ'
                 t > t_ or
                     t < Constants.rotation_period() * (div(t_, Constants.rotation_period()) - 1) ->
                   {:halt, {:error, "Invalid timeslot in guarantee"}}

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

  use Sizes

  defimpl Encodable do
    use Codec.Encoder
    alias Block.Extrinsic.Guarantee

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
end
