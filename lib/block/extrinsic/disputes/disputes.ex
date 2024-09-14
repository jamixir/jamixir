defmodule Block.Extrinsic.Disputes do
  @moduledoc """
  Formula (98) v0.3.4
  Represents a disputes in the blockchain system, containing a list of verdicts, and optionally, culprits and faults.
  """

  alias Block.Extrinsic.Disputes
  alias Block.Extrinsic.Disputes.{Culprit, Fault, Judgement, Verdict}
  alias System.State.{Judgements, Validator}
  alias Util.{Collections, Crypto, Time}

  @type t :: %__MODULE__{
          # v
          verdicts: list(Verdict.t()),
          # c
          culprits: list(Culprit.t()),
          # f
          faults: list(Fault.t())
        }

  defstruct verdicts: [], culprits: [], faults: []

  @spec validate_disputes(
          Disputes.t(),
          list(Validator.t()),
          list(Validator.t()),
          Judgements.t(),
          integer()
        ) ::
          :ok | {:error, String.t()}
  def validate_disputes(
        %Disputes{verdicts: verdicts, culprits: culprits, faults: faults},
        curr_validators,
        prev_validators,
        judgements,
        timeslot
      ) do
    with :ok <-
           validate_verdicts(verdicts, curr_validators, prev_validators, judgements, timeslot),
         allowed_validator_keys <-
           compute_allowed_validator_keys(curr_validators, prev_validators, judgements),
         bad_set <- compute_bad_set(verdicts, judgements),
         :ok <- validate_offenses(culprits, allowed_validator_keys, bad_set, :culprits),
         :ok <- validate_offenses(faults, allowed_validator_keys, bad_set, :faults) do
      :ok
    else
      error -> error
    end
  end

  defp validate_verdicts([], _, _, _, _), do: :ok

  defp validate_verdicts(verdicts, curr_validators, prev_validators, judgements, timeslot) do
    current_epoch = Time.epoch_index(timeslot)

    cond do
      # Formula (99) v0.3.4 - epoch index
      !Enum.all?(verdicts, &(&1.epoch_index in [current_epoch, current_epoch - 1])) ->
        {:error, "Invalid epoch index in verdicts"}

      # Formula (98) v0.3.4 - required length ⌊2/3V⌋+1
      !Enum.all?(verdicts, fn %Verdict{judgements: judgements, epoch_index: epoch_index} ->
        validator_set =
            get_validator_set(curr_validators, prev_validators, current_epoch, epoch_index)

        length(judgements) == div(2 * length(validator_set), 3) + 1
      end) ->
        {:error, "Invalid number of judgements in verdicts"}

      # Formula (103) v0.3.4
      !match?(
        :ok,
        Collections.validate_unique_and_ordered(verdicts, & &1.work_report_hash)
      ) ->
        {:error, "Invalid order or duplicates in verdict work report hashes"}

      # Formula (105) v0.3.4
      !MapSet.disjoint?(
        Judgements.union_all(judgements),
        MapSet.new(verdicts, & &1.work_report_hash)
      ) ->
        {:error, "Work report hashes already exist in current judgments"}

      #  Formula (99) v0.3.4 - signatures
      !Enum.all?(verdicts, fn verdict ->
        curr_validators
        |> get_validator_set(prev_validators, current_epoch, verdict.epoch_index)
        |> valid_signatures?(verdict)
      end) ->
        {:error, "Invalid signatures in verdicts"}

      # Formula (106) v0.3.4
      !Collections.all_ok?(verdicts, fn %Verdict{judgements: judgements} ->
        Collections.validate_unique_and_ordered(judgements, & &1.validator_index)
      end) ->
        {:error, "Judgements not ordered by validator index or contain duplicates"}

      # Formula (107) v0.3.4
      # Formula (108) v0.3.4
      Enum.any?(verdicts, fn verdict ->
        validator_count =
            length(
              get_validator_set(
                curr_validators,
                prev_validators,
                current_epoch,
                verdict.epoch_index
              )
            )

        Verdict.sum_judgements(verdict) not in [
          0,
          div(validator_count, 3),
          div(2 * validator_count, 3) + 1
        ]
      end) ->
        {:error, "Invalid sum of judgements in verdicts"}

      true ->
        :ok
    end
  end

  # Formula (101) v0.3.4
  # Formula (102) v0.3.4
  defp compute_allowed_validator_keys(curr_validators, prev_validators, judgements) do
    MapSet.union(
      MapSet.new(curr_validators, & &1.ed25519),
      MapSet.new(prev_validators, & &1.ed25519)
    )
    |> MapSet.difference(judgements.punish)
  end

  # Formula (112) v0.3.4
  defp compute_bad_set(verdicts, judgements) do
    verdicts
    |> Enum.filter(&(Verdict.sum_judgements(&1) == 0))
    |> Enum.map(& &1.work_report_hash)
    |> MapSet.new()
    |> MapSet.union(judgements.bad)
  end

  defp validate_offenses([], _, _, _), do: :ok

  defp validate_offenses(offenses, allowed_validator_keys, posterior_bad_set, offense_type) do
    cond do
      # Formula 104
      !match?(
        :ok,
        Collections.validate_unique_and_ordered(offenses, & &1.validator_key)
      ) ->
        {:error, "Invalid order or duplicates in #{offense_type} Ed25519 keys"}

      # Formula 101 and 102 -Check: Ensure all offense work report hashes are in the posterior bad set
      !Enum.all?(offenses, &MapSet.member?(posterior_bad_set, &1.work_report_hash)) ->
        {:error, "Work report hash in #{offense_type} not in the posterior bad set"}

      # Formula 101 and 102 - Check if all offense validator keys are valid
      !Enum.all?(offenses, &MapSet.member?(allowed_validator_keys, &1.validator_key)) ->
        {:error, "#{offense_type} reported for a validator not in the allowed validator keys"}

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

  # Formula (99) v0.3.4
  def get_validator_set(curr_validators, _prev_validators, current_epoch, current_epoch),
    do: curr_validators

  def get_validator_set(_curr_validators, prev_validators, current_epoch, epoch_index)
      when epoch_index == current_epoch - 1,
      do: prev_validators

  defp valid_signatures?(validator_set, %Verdict{judgements: judgements, work_report_hash: wrh}) do
    Enum.all?(judgements, fn judgement ->
      Crypto.verify_signature(
        judgement.signature,
        Judgement.signature_base(judgement) <> wrh,
        Enum.at(validator_set, judgement.validator_index).ed25519
      )
    end)
  end

  defimpl Encodable do
    def encode(%Disputes{}) do
      # TODO
    end
  end
end
