defmodule Block.Extrinsic.Guarantee do
  @moduledoc """
  Work report guarantee.
  11.4
  Formula (138) v0.3.4
  """
  alias Util.Hash
  alias Block.Extrinsic.Guarantor
  alias System.State.EntropyPool
  alias Util.Crypto
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Util.Collections
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
  @spec validate(list(t())) :: :ok | {:error, String.t()}
  def validate(guarantees) do
    with :ok <- Collections.validate_unique_and_ordered(guarantees, & &1.work_report.core_index),
         true <-
           Enum.all?(guarantees, fn %__MODULE__{credentials: cred} ->
             length(cred) in [2, 3]
           end),
         true <-
           Collections.all_ok?(guarantees, fn %__MODULE__{credentials: cred} ->
             # Formula (139) v0.3.4
             Collections.validate_unique_and_ordered(cred, &elem(&1, 0))
           end) do
      :ok
    else
      {:error, :duplicates} -> {:error, "Duplicate core_index found in guarantees"}
      {:error, :not_in_order} -> {:error, "Guarantees not ordered by core_index"}
      false -> {:error, "Invalid credentials in one or more guarantees"}
      {:error, reason} -> {:error, reason}
    end
  end

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
        case Enum.reduce_while(a, {:ok, reporters_set}, fn {v, s}, {:ok, acum2} ->
               # (kv)e
               validator_key = Enum.at(validators, v).ed25519
               # XG ⌢ H(E(w))
               payload = SigningContexts.jam_guarantee() <> Hash.default(Codec.Encoder.encode(w))

               # s ∈ E(k ) ⟨XG ⌢ H(E(w))⟩
               # cv = wc ∧ R(⌊τ′/R⌋−1) ≤ t ≤ τ'
               if Crypto.valid_signature?(s, payload, validator_key) and
                    Enum.at(c, v) == wc and
                    t <= t_ and
                    t >= Constants.rotation_period() * (div(t_, Constants.rotation_period()) - 1) do
                 # k ∈ R ⇔ ∃(w, t, a) ∈ EG, ∃(v, s) ∈ a ∶ k = (kv)e
                 {:cont, {:ok, MapSet.put(acum2, validator_key)}}
               else
                 {:halt, {:error, "Invalid guarantee"}}
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

  def mock(:reporters_set, _), do: {:ok, MapSet.new()}

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
