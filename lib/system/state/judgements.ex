defmodule System.State.Judgements do
  @moduledoc """
  Represents the state and operations related to judgements in the disputes system.
  """
  alias Block.Extrinsic.Disputes
  alias Block.Extrinsic.Disputes.Verdict
  alias Block.Header
  alias System.State.Judgements

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

  def posterior_judgements(%Header{timeslot: ts}, disputes, state) do
    # Formula (115) v0.3.4
    new_punish_set =
      MapSet.union(
        state.judgements.punish,
        MapSet.new(disputes.culprits ++ disputes.faults, & &1.validator_key)
      )

    %Judgements{
      posterior_judgement_sets(
        Map.get(disputes, :verdicts),
        state.curr_validators,
        state.prev_validators,
        state.judgements,
        ts
      )
      | punish: new_punish_set
    }
  end

  defp posterior_judgement_sets(verdicts, curr_validators, prev_validators, judgements, timeslot) do
    current_epoch = Util.Time.epoch_index(timeslot)

    Enum.reduce(
      verdicts,
      judgements,
      fn verdict, acc ->
        validator_count =
          length(
            Disputes.get_validator_set(
              curr_validators,
              prev_validators,
              current_epoch,
              verdict.epoch_index
            )
          )

        sum_judgements = Verdict.sum_judgements(verdict)

        cond do
          # Formula (112) v0.3.4
          sum_judgements == div(2 * validator_count, 3) + 1 ->
            %{acc | good: MapSet.put(acc.good, verdict.work_report_hash)}

          # Formula (113) v0.3.4
          sum_judgements == 0 ->
            %{acc | bad: MapSet.put(acc.bad, verdict.work_report_hash)}

          # Formula (114) v0.3.4
          sum_judgements == div(validator_count, 3) ->
            %{acc | wonky: MapSet.put(acc.wonky, verdict.work_report_hash)}

          true ->
            acc
        end
      end
    )
  end

  def union_all(%__MODULE__{good: g, bad: b, wonky: w}) do
    MapSet.union(g, b) |> MapSet.union(w)
  end

  defimpl Encodable do
    alias Codec.VariableSize
    # E(↕[x^x ∈ ψg],↕[x^x ∈ ψb],↕[x^x ∈ ψw],↕[x^x ∈ ψo])
    def encode(%Judgements{} = j) do
      Codec.Encoder.encode({
        VariableSize.new(j.good),
        VariableSize.new(j.bad),
        VariableSize.new(j.wonky),
        VariableSize.new(j.punish)
      })
    end
  end
end
