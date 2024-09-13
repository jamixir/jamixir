defmodule Block.Extrinsic.Disputes do
  @moduledoc """
  Formula (98) v0.3.4
  Represents a disputes in the blockchain system, containing a list of verdicts, and optionally, culprits and faults.
  """

  alias Block.Extrinsic.Disputes
  alias Block.Extrinsic.Disputes.{Culprit, Fault, Helper, ProcessedVerdict, Verdict}
  alias Block.Header
  alias System.State
  alias Types
  alias Util.Crypto

  @type t :: %__MODULE__{
          # v
          verdicts: list(Verdict.t()),
          # c
          culprits: list(Culprit.t()),
          # f
          faults: list(Fault.t())
        }

  defstruct verdicts: [], culprits: [], faults: []

  @doc """
  Filters all components of Disputes extrinsic (verdicts, culprits, faults) for validity.
  """
  def validate_and_process_disputes(%Disputes{} = disputes, %State{} = state, %Header{
        timeslot: timeslot
      }) do
    processed_verdicts_map = Helper.process_verdicts(disputes.verdicts, state, timeslot)

    # Filter out verdicts that already exist in the state sets
    unique_processed_verdicts_map = filter_duplicates(processed_verdicts_map, state.judgements)

    valid_offenses =
      filter_valid_offenses(
        disputes.culprits ++ disputes.faults,
        unique_processed_verdicts_map,
        state
      )

    {unique_processed_verdicts_map, valid_offenses}
  end

  # Filters and returns only valid offenses (culprits and faults).

  defp filter_valid_offenses(offenses, processed_verdicts_map, state) do
    offenses
    |> Enum.filter(fn offense ->
      valid_signature?(offense, processed_verdicts_map) and
        MapSet.member?(combined_validators(state), offense.validator_key) and
        offense_in_new_bad_set?(offense, processed_verdicts_map, state)
    end)
    # Formula (104) v0.3.4
    |> Util.Collections.uniq_sorted(& &1.validator_key)
  end

  defp valid_signature?(%Culprit{validator_key: key, signature: sig, work_report_hash: wrh}, _) do
    Crypto.verify_signature(sig, wrh, key)
  end

  defp valid_signature?(%Fault{validator_key: key, signature: sig, work_report_hash: wrh}, _) do
    Crypto.verify_signature(sig, wrh, key)
  end

  # Formula (101) and 102 v0.3.4.
  defp combined_validators(state) do
    current_validators = state.curr_validators |> Enum.map(& &1.ed25519)
    previous_validators = state.prev_validators |> Enum.map(& &1.ed25519)
    punished_keys = MapSet.to_list(state.judgements.punish)

    combined = current_validators ++ previous_validators
    (combined -- punished_keys) |> MapSet.new()
  end

  # Formula (101) v0.3.4
  # Formula (102) v0.3.4
  # Validates whether an offense (culprit or fault) is valid based on
  # report_hash being in the bad set or in the verdict bad set

  @spec offense_in_new_bad_set?(map(), %{Types.hash() => ProcessedVerdict.t()}, State.t()) ::
          boolean()
  defp offense_in_new_bad_set?(
         %{work_report_hash: report_hash},
         processed_verdicts_map,
         state
       ) do
    classification =
      case Map.get(processed_verdicts_map, report_hash) do
        %ProcessedVerdict{classification: classification} -> classification
        _ -> nil
      end

    classification == :bad or report_hash in state.judgements.bad
  end

  # Formula (105) v0.3.4.
  defp filter_duplicates(processed_verdicts_map, %System.State.Judgements{
         good: good_set,
         bad: bad_set,
         wonky: wonky_set
       }) do
    Enum.reject(processed_verdicts_map, fn {hash, _} ->
      hash in good_set or hash in bad_set or hash in wonky_set
    end)
    |> Enum.into(%{})
  end

  defimpl Encodable do
    def encode(%Disputes{}) do
      # TODO
    end
  end
end
