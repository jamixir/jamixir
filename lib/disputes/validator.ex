defmodule Disputes.Validator do
  alias Block.{Header}
  alias Disputes.{Verdict, Culprit, Fault, Helper}
  alias System.State
  alias System.State.{Validator, Judgements}
  alias Types

  @doc """
  Filters all components of Disputes extrinsic (verdicts, culprits, faults) for validity.
  """
  def filter_all_components(%Disputes{} = disputes, %State{} = state, %Header{timeslot: timeslot}) do
    valid_verdicts = filter_valid_verdicts(disputes.verdicts, state, timeslot)
    verdict_scores = Helper.create_verdicts_scores(valid_verdicts)

    valid_culprits = filter_valid_culprits(disputes.culprits, verdict_scores, state)
    valid_faults = filter_valid_faults(disputes.faults, verdict_scores, state)

    {valid_verdicts, valid_culprits, valid_faults, verdict_scores}
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
    Enum.filter(verdicts, &Helper.valid_verdict?(&1, state, timeslot))
    |> Enum.uniq_by(& &1.work_report_hash)
  end

  @doc """
  Filters and returns only valid culprits.
  """
  def filter_valid_culprits(culprits, verdicts, state) do
    culprits
    |> Enum.filter(&Culprit.valid_signature?/1)
    |> Enum.filter(&Helper.valid_offense?(&1, verdicts, state))
    |> Enum.uniq_by(& &1.validator_key)
  end

  @doc """
  Filters and returns only valid faults.
  """
  def filter_valid_faults(faults, verdicts, state) do
    faults
    |> Enum.filter(&Fault.valid_signature?/1)
    |> Enum.filter(&Helper.valid_offense?(&1, verdicts, state))
    |> Enum.uniq_by(& &1.validator_key)
  end
end
