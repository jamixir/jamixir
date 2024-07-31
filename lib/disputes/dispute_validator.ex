defmodule Disputes.Validator do
  alias Block.{Header}
  alias Disputes.{Verdict, Culprit, Fault}
  alias Util.Time
  alias System.State

  def filter_all_components(%Disputes{} = disputes, %State{} = state, %Header{timeslot: timeslot}) do
    valid_verdicts = filter_valid_verdicts(disputes.verdicts, state, timeslot)
    valid_report_hashes = Enum.map(valid_verdicts, & &1.report_hash)

    valid_culprits = filter_valid_culprits(disputes.culprits, valid_report_hashes, state)
    valid_faults = filter_valid_faults(disputes.faults, valid_report_hashes, state)

    {valid_verdicts, valid_culprits, valid_faults}
  end

  @doc """
  Filters and returns only valid verdicts.
  """
  @spec filter_valid_verdicts(
          list(Verdict.t()),
          %State{
            curr_validators: list(Validator.t()),
            prev_validators: list(Validator.t()),
            judgements: Judgements.t()
          },
          integer()
        ) :: list(Verdict.t())
  def filter_valid_verdicts(verdicts, state, timeslot) do
    Enum.filter(verdicts, &valid_verdict?(&1, state, timeslot))
  end

  # Public function to filter valid culprits
  def filter_valid_culprits(culprits, valid_report_hashes, state) do
    culprits
    |> Enum.filter(&Culprit.valid_signature?/1)
    |> filter_valid_offenses(valid_report_hashes, state)
  end

  # Public function to filter valid faults
  def filter_valid_faults(faults, valid_report_hashes, state) do
    faults
    |> Enum.filter(&Fault.valid_signature?/1)
    |> filter_valid_offenses(valid_report_hashes, state)
  end

  # Private function to check if a verdict is valid
  defp valid_verdict?(verdict, state, header) do
    valid_epoch_index?(verdict, header) and enough_valid_judgements?(verdict, state, header)
  end

  # Private function to validate the epoch index
  defp valid_epoch_index?(%Verdict{epoch_index: epoch_index}, %Header{timeslot: timeslot}) do
    current_epoch_index = Time.epoch_index(timeslot)
    (current_epoch_index - epoch_index) in [0, 1]
  end

  # Private function to get the appropriate validator set
  defp validator_set(
         %Verdict{epoch_index: epoch_index},
         %State{curr_validators: curr_validators, prev_validators: prev_validators},
         %Header{timeslot: timeslot}
       ) do
    current_epoch_index = Time.epoch_index(timeslot)

    case current_epoch_index - epoch_index do
      0 -> curr_validators
      1 -> prev_validators
    end
  end

  # Private function to count the required number of judgements
  defp required_judgement_count(validators) do
    div(length(validators) * 2, 3) + 1
  end

  # Private function to check if there are enough valid judgements
  defp enough_valid_judgements?(%Verdict{judgements: judgements} = verdict, state, header) do
    validator_set = validator_set(verdict, state, header)

    valid_judgments =
      Enum.filter(judgements, fn %Judgement{signature: sig} ->
        signature_in_validators?(sig, validator_set)
      end)

    length(valid_judgments) >= required_judgement_count(validator_set)
  end

  # Private function to check if a signature is in the list of validators
  defp signature_in_validators?(signature, validators) do
    Enum.any?(validators, fn %Validator{ed25519: key} -> key == signature end)
  end

  # Private function to filter valid offenses (culprits or faults)
  defp filter_valid_offenses(offenses, valid_report_hashes, state) do
    Enum.filter(offenses, fn %{
                               report_hash: report_hash,
                               validator_key: key
                             } ->
      report_hash in valid_report_hashes and not MapSet.member?(state.judgements.punish, key)
    end)
    |> Enum.uniq_by(& &1.validator_key)
  end
end
