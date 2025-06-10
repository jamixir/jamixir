defmodule Block.Extrinsic.Disputes do
  @moduledoc """
  Formula (10.2) v0.6.6
  """

  alias Block.Extrinsic.Disputes
  alias Codec.VariableSize
  alias Block.Extrinsic.Disputes.{Culprit, Error, Fault, Judgement, Verdict}
  alias System.State.{Judgements, Validator}
  alias Util.{Collections, Crypto, Time}
  use MapUnion

  @type t :: %__MODULE__{
          # v
          verdicts: list(Verdict.t()),
          # c
          culprits: list(Culprit.t()),
          # f
          faults: list(Fault.t())
        }

  defstruct verdicts: [], culprits: [], faults: []

  @spec validate(
          Disputes.t(),
          list(Validator.t()),
          list(Validator.t()),
          Judgements.t(),
          integer()
        ) ::
          :ok | {:error, String.t()}
  def validate(
        %Disputes{verdicts: verdicts, culprits: culprits, faults: faults} = disputes,
        curr_validators,
        prev_validators,
        judgements,
        timeslot
      ) do
    state = %System.State{
      curr_validators: curr_validators,
      prev_validators: prev_validators,
      timeslot: timeslot
    }

    with :ok <-
           validate_verdicts(verdicts, curr_validators, prev_validators, judgements, timeslot),
         {:ok, v_set} <- Judgements.calculate_v(disputes, state),
         allowed_validator_keys <-
           compute_allowed_validator_keys(curr_validators, prev_validators, judgements),
         bad_set <- compute_bad_set(verdicts, judgements),
         :ok <- validate_culprits(culprits, allowed_validator_keys, bad_set),
         :ok <- validate_faults(faults, allowed_validator_keys, v_set) do
      :ok
    else
      error -> error
    end
  end

  defp validate_verdicts([], _, _, _, _), do: :ok

  defp validate_verdicts(verdicts, curr_validators, prev_validators, judgements, timeslot) do
    current_epoch = Time.epoch_index(timeslot)

    cond do
      # Formula (10.2) - epoch index
      !Enum.all?(verdicts, &(&1.epoch_index in [current_epoch, current_epoch - 1])) ->
        {:error, Error.bad_judgement_age()}

      # Formula (10.2) - required length ⌊2/3V⌋+1
      !Enum.all?(verdicts, fn %Verdict{judgements: judgements, epoch_index: epoch_index} ->
        validator_set =
            get_validator_set(curr_validators, prev_validators, current_epoch, epoch_index)

        length(judgements) == div(2 * length(validator_set), 3) + 1
      end) ->
        {:error, Error.bad_vote_split()}

      # Formula (10.7) v0.6.6
      !match?(
        :ok,
        Collections.validate_unique_and_ordered(verdicts, & &1.work_report_hash)
      ) ->
        {:error, Error.unsorted_verdicts()}

      # Formula (10.9) v0.6.6
      !MapSet.disjoint?(
        Judgements.union_all(judgements),
        MapSet.new(verdicts, & &1.work_report_hash)
      ) ->
        {:error, Error.already_judged()}

      #  Formula (10.3) v0.6.6 - signatures
      !Enum.all?(verdicts, fn verdict ->
        curr_validators
        |> get_validator_set(prev_validators, current_epoch, verdict.epoch_index)
        |> valid_signatures?(verdict)
      end) ->
        {:error, Error.invalid_signature()}

      # Formula (10.10) v0.6.6
      !Collections.all_ok?(verdicts, fn %Verdict{judgements: judgements} ->
        Collections.validate_unique_and_ordered(judgements, & &1.validator_index)
      end) ->
        {:error, Error.unsorted_judgements()}

      # Formula (10.11) v0.6.6
      # Formula (10.12) v0.6.6
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
        {:error, Error.bad_vote_split()}

      true ->
        :ok
    end
  end

  # Formula (10.5) v0.6.6
  # Formula (10.6) v0.6.6
  defp compute_allowed_validator_keys(curr_validators, prev_validators, judgements) do
    MapSet.new(curr_validators, & &1.ed25519) ++ MapSet.new(prev_validators, & &1.ed25519) \\ judgements.offenders
  end

  # Formula (10.17) v0.6.6
  defp compute_bad_set(verdicts, judgements) do
    for v <- verdicts, Verdict.sum_judgements(v) == 0, into: MapSet.new() do
      v.work_report_hash
    end ++ judgements.bad
  end

  defp validate_common_offense_rules(offenses, allowed_validator_keys, offense_type) do
    cond do
      # Formula (10.8) v0.6.6
      !match?(:ok, Collections.validate_unique_and_ordered(offenses, & &1.key)) ->
        {:error,
         if(offense_type == :faults, do: Error.unsorted_faults(), else: Error.unsorted_culprits())}

      # Formula 10.5 and 1.6 - Check if all offense validator keys are valid
      !Enum.all?(offenses, &(&1.key in allowed_validator_keys)) ->
        {:error, Error.offender_already_reported()}

      # Formula 10.5 and 10.6 - Check signatures
      !Enum.all?(
        offenses,
        fn offense ->
          msg_base =
              case offense_type do
                :culprits ->
                  SigningContexts.jam_guarantee()

                :faults ->
                  if offense.vote,
                    do: SigningContexts.jam_valid(),
                    else: SigningContexts.jam_invalid()
              end

          Crypto.valid_signature?(
            offense.signature,
            msg_base <> offense.work_report_hash,
            offense.key
          )
        end
      ) ->
        {:error, Error.invalid_signature()}

      true ->
        :ok
    end
  end

  defp validate_culprits([], _, _), do: :ok

  defp validate_culprits(culprits, allowed_validator_keys, bad_set) do
    with :ok <- validate_common_offense_rules(culprits, allowed_validator_keys, :culprits) do
      if Enum.all?(culprits, &(&1.work_report_hash in bad_set)) do
        :ok
      else
        {:error, Error.culprit_verdict_not_bad()}
      end
    end
  end

  defp validate_faults([], _, _), do: :ok

  defp validate_faults(faults, allowed_validator_keys, v_set) do
    with :ok <- validate_common_offense_rules(faults, allowed_validator_keys, :faults) do
      if Enum.any?(faults, fn fault ->
           case Enum.find(v_set, fn {hash, _sum, _v_count} -> hash == fault.work_report_hash end) do
             {_, sum, v_count} when sum == div(2 * v_count, 3) + 1 -> fault.vote
             {_, 0, _} -> !fault.vote
             _ -> false
           end
         end) do
        {:error, Error.fault_verdict_wrong()}
      else
        :ok
      end
    end
  end

  # Formula (10.3) v0.6.6
  def get_validator_set(curr_validators, _prev_validators, current_epoch, current_epoch),
    do: curr_validators

  def get_validator_set(_curr_validators, prev_validators, current_epoch, epoch_index)
      when epoch_index == current_epoch - 1,
      do: prev_validators

  defp valid_signatures?(validator_set, %Verdict{judgements: judgements, work_report_hash: wrh}) do
    Enum.all?(judgements, fn judgement ->
      Crypto.valid_signature?(
        judgement.signature,
        Judgement.signature_base(judgement) <> wrh,
        Enum.at(validator_set, judgement.validator_index).ed25519
      )
    end)
  end

  defimpl Encodable do
    import Codec.Encoder

    # Formula (C.18) v0.6.6
    def encode(%Disputes{} = d) do
      e({vs(d.verdicts), vs(d.culprits), vs(d.faults)})
    end
  end

  def decode(bin) do
    {verdicts, bin} = VariableSize.decode(bin, Verdict)
    {culprits, bin} = VariableSize.decode(bin, Culprit)
    {faults, rest} = VariableSize.decode(bin, Fault)

    {%Disputes{verdicts: verdicts, culprits: culprits, faults: faults}, rest}
  end

  use JsonDecoder
  def json_mapping, do: %{verdicts: [Verdict], culprits: [Culprit], faults: [Fault]}
end
