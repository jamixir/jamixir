defmodule Block.Extrinsic.Disputes do
  @moduledoc """
  Formula (98) v0.3.4
  Represents a disputes in the blockchain system, containing a list of verdicts, and optionally, culprits and faults.
  """

  alias Block.Extrinsic.Disputes.{Verdict, Culprit, Fault}
  alias Block.Extrinsic.Disputes
  alias System.State
  alias Util.{Time, Crypto, Collections}

  @type t :: %__MODULE__{
          # v
          verdicts: list(Verdict.t()),
          # c
          culprits: list(Culprit.t()),
          # f
          faults: list(Fault.t())
        }

  defstruct verdicts: [], culprits: [], faults: []

  @spec validate_disputes(Disputes.t(), State.t(), integer()) ::
          {:ok, any()} | {:error, String.t()}
  def validate_disputes(
        %Disputes{verdicts: verdicts, culprits: culprits, faults: faults},
        state,
        timeslot
      ) do
    with :ok <- validate_verdicts(verdicts, state, timeslot),
         {:ok, v} <- process_verdicts(verdicts, state, timeslot),
         allowed_validator_keys <- compute_allowed_validator_keys(state),
         :ok <- validate_offenses(culprits, allowed_validator_keys, v.bad_set, :culprits),
         :ok <- validate_offenses(faults, allowed_validator_keys, v.bad_set, :faults) do
      {:ok, v}
    end
  end

  defp compute_allowed_validator_keys(state) do
    MapSet.union(
      MapSet.new(state.curr_validators, & &1.ed25519),
      MapSet.new(state.prev_validators, & &1.ed25519)
    )
    |> MapSet.difference(state.judgements.punish)
  end

  defp validate_verdicts([], _, _), do: :ok

  defp validate_verdicts(verdicts, state, timeslot) do
    current_epoch = Time.epoch_index(timeslot)

    cond do
      # Formula (99) v0.3.4 - epoch index
      !Enum.all?(verdicts, &(&1.epoch_index in [current_epoch, current_epoch - 1])) ->
        {:error, "Invalid epoch index in verdicts"}

      # Formula (98) v0.3.4 - required length ⌊2/3V⌋+1
      !Enum.all?(verdicts, &valid_judgement_count?(&1, state, current_epoch)) ->
        {:error, "Invalid number of judgements in verdicts"}

      # Formula (103) v0.3.4
      !match?(
        {:ok, :valid},
        Collections.validate_unique_and_ordered(verdicts, & &1.work_report_hash)
      ) ->
        {:error, "Invalid order or duplicates in verdict work report hashes"}

      # Formula (105) v0.3.4
      !disjoint_from_existing_judgments?(verdicts, state.judgements) ->
        {:error, "Work report hashes already exist in current judgments"}

      #  Formula (99) v0.3.4 - signatures
      !Enum.all?(verdicts, &valid_signatures?(&1, state, current_epoch)) ->
        {:error, "Invalid signatures in verdicts"}

      # Formula (106) v0.3.4
      !Enum.all?(verdicts, fn %Verdict{judgements: judgements} ->
        match?(
          {:ok, :valid},
          Collections.validate_unique_and_ordered(judgements, & &1.validator_index)
        )
      end) ->
        {:error, "Judgements not ordered by validator index or contain duplicates"}

      # Formula (107) v0.3.4 and Formula (108) v0.3.4
      Enum.any?(verdicts, &invalid_sum?(state, &1, current_epoch)) ->
        {:error, "Invalid sum of judgements in verdicts"}

      true ->
        :ok
    end
  end

  defp process_verdicts(verdicts, state, timeslot) do
    current_epoch = Time.epoch_index(timeslot)

    # Formula (112) v0.3.4
    good_set =
      verdicts
      |> Enum.filter(
        &(sum_judgements(&1) == div(2 * validator_count(state, &1, current_epoch), 3) + 1)
      )
      |> Enum.map(& &1.work_report_hash)
      |> MapSet.new()

    # Formula (113) v0.3.4
    bad_set =
      verdicts
      |> Enum.filter(&(sum_judgements(&1) == 0))
      |> Enum.map(& &1.work_report_hash)
      |> MapSet.new()

    # Formula (114) v0.3.4
    wonky_set =
      verdicts
      |> Enum.filter(&(sum_judgements(&1) == div(validator_count(state, &1, current_epoch), 3)))
      |> Enum.map(& &1.work_report_hash)
      |> MapSet.new()

    {:ok, %{good_set: good_set, bad_set: bad_set, wonky_set: wonky_set}}
  end

  defp validate_offenses([], _, _, _), do: :ok

  defp validate_offenses(offenses, allowed_validator_keys, posterior_bad_set, offense_type) do
    cond do
      # Formula 104
      !match?(
        {:ok, :valid},
        Collections.validate_unique_and_ordered(offenses, & &1.validator_key)
      ) ->
        {:error, "Invalid order or duplicates in #{offense_type} Ed25519 keys"}

      # Formula 101 and 102 -Check: Ensure all offense work report hashes are in the posterior bad set
      !Enum.all?(offenses, &MapSet.member?(posterior_bad_set, &1.work_report_hash)) ->
        {:error, "Work report hash in #{offense_type} not in the posterior bad set"}

      # Formula 101 and 102 - Check if all offense validator keys are valid
      !Enum.all?(offenses, &MapSet.member?(allowed_validator_keys, &1.validator_key)) ->
        {:error, "Invalid validator key in #{offense_type}"}

      # Formula 101 and 102 - Check signatures
      !Enum.all?(
        offenses,
        fn offense ->
          msg_base =
              case offense_type do
                :culprits ->
                  SigningContexts.jam_guarantee()

                :faults ->
                  if offense.decision,
                    do: SigningContexts.jam_valid(),
                    else: SigningContexts.jam_invalid()
              end

          Crypto.verify_signature(
            offense.signature,
            msg_base <> offense.work_report_hash,
            offense.validator_key
          )
        end
      ) ->
        {:error, "Invalid signature in #{offense_type}"}

      true ->
        :ok
    end
  end

  defp get_validator_set(state, current_epoch, verdict_epoch_index) do
    case current_epoch - verdict_epoch_index do
      0 -> state.curr_validators
      1 -> state.prev_validators
    end
  end

  defp valid_judgement_count?(
         %Verdict{judgements: judgements, epoch_index: epoch_index},
         state,
         current_epoch
       ) do
    validator_set = get_validator_set(state, current_epoch, epoch_index)
    required_judgements = div(2 * length(validator_set), 3) + 1
    length(judgements) == required_judgements
  end

  defp disjoint_from_existing_judgments?(verdicts, judgements) do
    MapSet.union(judgements.good, judgements.bad)
    |> MapSet.union(judgements.wonky)
    |> MapSet.disjoint?(MapSet.new(verdicts, & &1.work_report_hash))
  end

  defp valid_signatures?(
         %Verdict{judgements: judgements, work_report_hash: wrh, epoch_index: epoch_index},
         state,
         current_epoch
       ) do
    validator_set = get_validator_set(state, current_epoch, epoch_index)

    Enum.all?(judgements, fn judgement ->
      validator = Enum.at(validator_set, judgement.validator_index)

      signature_base =
        if judgement.decision,
          do: SigningContexts.jam_valid(),
          else: SigningContexts.jam_invalid()

      Crypto.verify_signature(judgement.signature, signature_base <> wrh, validator.ed25519)
    end)
  end

  defp sum_judgements(verdict) do
    verdict.judgements
    |> Enum.map(fn judgement -> if judgement.decision, do: 1, else: 0 end)
    |> Enum.sum()
  end

  defp invalid_sum?(state, verdict, current_epoch) do
    validator_count = length(get_validator_set(state, current_epoch, verdict.epoch_index))
    sum_judgements(verdict) not in [0, div(validator_count, 3), div(2 * validator_count, 3) + 1]
  end

  defp validator_count(state, verdict, current_epoch) do
    length(get_validator_set(state, current_epoch, verdict.epoch_index))
  end

  defimpl Encodable do
    def encode(%Disputes{}) do
      # TODO
    end
  end
end
