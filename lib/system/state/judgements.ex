defmodule System.State.Judgements do
  @moduledoc """
  Represents the state and operations related to judgements in the disputes system.
  """
  alias Block.Extrinsic.Disputes
  alias Block.Extrinsic.Disputes.Verdict
  alias Block.Header
  alias System.State.Judgements
  use SelectiveMock

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

  mockable posterior_judgements(%Header{timeslot: ts} = header, disputes, state) do
    # Formula (107) v0.3.4
    # Formula (108) v0.3.4
    v = calculate_v(disputes.verdicts, state, ts)

    # Formula (115) v0.3.4
    new_offenders =
      (disputes.culprits ++ disputes.faults)
      |> Enum.map(& &1.validator_key)

    if valid_header_markers?(
         header,
         v,
         new_offenders
       ) do
      {:ok,
       %Judgements{
         posterior_judgement_sets(v, state.judgements)
         | punish: MapSet.union(state.judgements.punish, MapSet.new(new_offenders))
       }}
    else
      {:error, "Header validation failed"}
    end
  end

  defp calculate_v(verdicts, state, timeslot) do
    current_epoch = Util.Time.epoch_index(timeslot)

    Enum.map(verdicts, fn verdict ->
      validator_set =
        Disputes.get_validator_set(
          state.curr_validators,
          state.prev_validators,
          current_epoch,
          verdict.epoch_index
        )

      {verdict.work_report_hash, Verdict.sum_judgements(verdict), length(validator_set)}
    end)
  end

  # Formula (116) v0.3.4
  # Formula (117) v0.3.4
  mockable valid_header_markers?(
             %Header{judgements_marker: jm, offenders_marker: of},
             v,
             new_offenders
           ) do
    bad_wonky_verdicts =
      Enum.filter(v, fn {_, sum, validator_count} ->
        sum != div(2 * validator_count, 3) + 1
      end)
      |> Enum.map(fn {hash, _, _} -> hash end)

    jm == bad_wonky_verdicts && of == new_offenders
  end

  defp posterior_judgement_sets(v, judgements) do
    Enum.reduce(v, judgements, fn {hash, sum, validator_count}, acc ->
      cond do
        # Formula (112) v0.3.4
        sum == div(2 * validator_count, 3) + 1 ->
          %{acc | good: MapSet.put(acc.good, hash)}

        # Formula (113) v0.3.4
        sum == 0 ->
          %{acc | bad: MapSet.put(acc.bad, hash)}

        # Formula (114) v0.3.4
        sum == div(validator_count, 3) ->
          %{acc | wonky: MapSet.put(acc.wonky, hash)}
      end
    end)
  end

  def union_all(%__MODULE__{good: g, bad: b, wonky: w}) do
    MapSet.union(g, b) |> MapSet.union(w)
  end

  def mock(:posterior_judgements, context), do: {:ok, Keyword.get(context, :state).judgements}
  def mock(:valid_header_markers?, _), do: true

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
