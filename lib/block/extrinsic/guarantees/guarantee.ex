defmodule Block.Extrinsic.Guarantee do
  @moduledoc """
  Work report guarantee.
  11.4
  Formula (138) v0.3.4
  """
  alias Block.Extrinsic.Guarantee.WorkResult
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Block.Extrinsic.Guarantor
  alias System.State
  alias System.State.EntropyPool
  alias Util.{Collections, Crypto, Hash}
  use SelectiveMock

  # {validator_index, ed25519 signature}
  @type credential :: {Types.validator_index(), Types.ed25519_signature()}

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
            credentials: [{0, <<0::512>>}]

  # Formula (138) v0.3.4
  # Formula (139) v0.3.4
  # Formula (140) v0.3.4
  @spec validate(list(t()), State.t(), integer()) :: :ok | {:error, String.t()}
  def validate(guarantees, state, timeslot) do
    with :ok <- Collections.validate_unique_and_ordered(guarantees, & &1.work_report.core_index),
         # Formula (145) v0.3.4
         :ok <- validate_gas(guarantees, state.services),
         # Formula (147) v0.3.4
         :ok <- validate_unique_wp_hash(guarantees),
         # Formula (149) v0.3.4
         :ok <- validate_refine_context_timeslot(guarantees, timeslot),
         true <-
           Enum.all?(guarantees, fn %__MODULE__{credentials: cred} -> length(cred) in [2, 3] end),
         # Formula (139) v0.3.4
         true <-
           Collections.all_ok?(guarantees, fn %__MODULE__{credentials: cred} ->
             Collections.validate_unique_and_ordered(cred, &elem(&1, 0))
           end) do
      :ok
    else
      {:error, error} -> {:error, error}
      false -> {:error, "Invalid credentials in one or more guarantees"}
    end
  end

  # Formula (143) v0.3.4 - w
  def work_reports(guarantees) do
    Enum.map(guarantees, & &1.work_report)
  end

  # Formula (146) v0.3.4 - x
  def refinement_contexts(guarantees) do
    work_reports(guarantees) |> Enum.map(& &1.refinement_context)
  end

  # Formula (145) v0.3.4
  def validate_gas(guarantees, services) do
    total_gas =
      work_reports(guarantees)
      |> Enum.flat_map(& &1.work_results)
      |> Enum.reduce(0, fn %WorkResult{service_index: s}, acum ->
        case Map.get(services, s) do
        # For now, when service is not in state, assume gas_limit_g is 0
          nil -> acum
          service -> acum + service.gas_limit_g
        end
      end)

    if total_gas <= Constants.gas_accumulation() do
      :ok
    else
      {:error, :invalid_gas_accumulation}
    end
  end

  # Formula (147) v0.3.4
  def validate_unique_wp_hash(guarantees) do
    wr = work_reports(guarantees)
    # Formula (146) v0.3.4
    p = MapSet.new(wr |> Enum.map(& &1.specification.work_package_hash))

    if length(wr) == MapSet.size(p) do
      :ok
    else
      {:error, :duplicated_wp_hash}
    end
  end

  def validate_refine_context_timeslot(guarantees, t) do
    # Formula
    if Enum.all?(
         refinement_contexts(guarantees),
         &(&1.timeslot >= t - Constants.max_age_lookup_anchor())
       ) do
      :ok
    else
      {:error, :refine_context_timeslot}
    end
  end

  def mock(:reporters_set, _), do: {:ok, MapSet.new()}

  # Formula (141) v0.3.4
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

  defimpl Encodable do
    alias Block.Extrinsic.Guarantee

    def encode(%Guarantee{}) do
      # TODO
      <<0>>
    end
  end
end
