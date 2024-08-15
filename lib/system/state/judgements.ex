defmodule System.State.Judgements do
  @moduledoc """
  Represents the state and operations related to judgements in the disputes system.
  """
  alias System.State.Judgements
  alias Block.Extrinsic.Disputes

  @type t :: %__MODULE__{
          good: MapSet.t(Types.hash()),
          bad: MapSet.t(Types.hash()),
          wonky: MapSet.t(Types.hash()),
          punish: MapSet.t(Types.ed25519_key())
        }

  # Formula (97) v0.3.4
  defstruct good: MapSet.new(),
            bad: MapSet.new(),
            wonky: MapSet.new(),
            punish: MapSet.new()

  @type verdict :: :good | :bad | :wonky

  def posterior_judgements(header, disputes, state) do
    {processed_verdicts_map, valid_offenses} =
      Disputes.validate_and_process_disputes(disputes, state, header)

    new_judgements = assimilate_judgements(state.judgements, processed_verdicts_map)
    new_punish_set = update_punish_set(new_judgements, valid_offenses)

    %Judgements{
      new_judgements
      | punish: new_punish_set
    }
  end

  defp assimilate_judgements(
         %System.State.Judgements{} = state_judgements,
         processed_verdicts_map
       ) do
    {new_goodset, new_badset, new_wonkyset} =
      Enum.reduce(
        processed_verdicts_map,
        {state_judgements.good, state_judgements.bad, state_judgements.wonky},
        fn
          {_hash, %Disputes.ProcessedVerdict{classification: :good, work_report_hash: hash}},
          {good_acc, bad_acc, wonky_acc} ->
            {MapSet.put(good_acc, hash), bad_acc, wonky_acc}

          {_hash, %Disputes.ProcessedVerdict{classification: :bad, work_report_hash: hash}},
          {good_acc, bad_acc, wonky_acc} ->
            {good_acc, MapSet.put(bad_acc, hash), wonky_acc}

          {_hash, %Disputes.ProcessedVerdict{classification: :wonky, work_report_hash: hash}},
          {good_acc, bad_acc, wonky_acc} ->
            {good_acc, bad_acc, MapSet.put(wonky_acc, hash)}

          _, acc ->
            acc
        end
      )

    %System.State.Judgements{
      state_judgements
      | good: new_goodset,
        bad: new_badset,
        wonky: new_wonkyset
    }
  end

  defp update_punish_set(state_judgements, offenses) do
    Enum.reduce(offenses, state_judgements.punish, fn offense, acc ->
      MapSet.put(acc, offense.validator_key)
    end)
  end
end
