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
          # g
          good: MapSet.t(Types.hash()),
          # b
          bad: MapSet.t(Types.hash()),
          # w
          wonky: MapSet.t(Types.hash()),
          # o
          punish: MapSet.t(Types.ed25519_key())
        }

  # Formula (97) v0.4.1
  defstruct good: MapSet.new(),
            bad: MapSet.new(),
            wonky: MapSet.new(),
            punish: MapSet.new()

  mockable calculate_judgements_(%Header{timeslot: ts} = header, disputes, state) do
    # Formula (107) v0.4.1
    # Formula (108) v0.4.1
    case calculate_v(disputes, state, ts) do
      {:ok, v} ->
        bad_wonky_verdicts =
          Enum.filter(v, fn {_, sum, validator_count} ->
            sum != div(2 * validator_count, 3) + 1
          end)
          |> Enum.map(fn {hash, _, _} -> hash end)

        # Formula (115) v0.4.1
        new_offenders =
          (disputes.culprits ++ disputes.faults)
          |> Enum.map(& &1.validator_key)

        if valid_header_markers?(
             header,
             bad_wonky_verdicts,
             new_offenders
           ) do
          {:ok,
           %Judgements{
             posterior_judgement_sets(v, state.judgements)
             | punish: MapSet.union(state.judgements.punish, MapSet.new(new_offenders))
           }, bad_wonky_verdicts}
        else
          {:error, "Header validation failed"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calculate_v(%Disputes{verdicts: verdicts, culprits: c, faults: f}, state, timeslot) do
    current_epoch = Util.Time.epoch_index(timeslot)

    v_set =
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

    case Enum.any?(v_set, fn {r, sum, v_count} ->
         # Formula (110) v0.4.1
         culprits_check = sum == 0 && length(Enum.filter(c, &(&1.work_report_hash == r))) < 2

         # Formula (109) v0.4.1
         faults_check =
           sum == div(2 * v_count, 3) + 1 &&
             Enum.empty?(Enum.filter(f, &(&1.work_report_hash == r)))

         culprits_check or faults_check
       end) do
      true ->
        {:error, :invalid_v_set}

      false ->
        {:ok, v_set}
    end
  end

  # Formula (116) v0.4.1
  mockable(
    valid_header_markers?(
      %Header{offenders_marker: of},
      bad_wonky_verdicts,
      new_offenders
    ),
    do: of == new_offenders
  )

  defp posterior_judgement_sets(v, judgements) do
    Enum.reduce(v, judgements, fn {hash, sum, validator_count}, acc ->
      cond do
        # Formula (112) v0.4.1
        sum == div(2 * validator_count, 3) + 1 ->
          %{acc | good: MapSet.put(acc.good, hash)}

        # Formula (113) v0.4.1
        sum == 0 ->
          %{acc | bad: MapSet.put(acc.bad, hash)}

        # Formula (114) v0.4.1
        sum == div(validator_count, 3) ->
          %{acc | wonky: MapSet.put(acc.wonky, hash)}
      end
    end)
  end

  def union_all(%__MODULE__{good: g, bad: b, wonky: w}) do
    MapSet.union(g, b) |> MapSet.union(w)
  end

  def mock(:calculate_judgements_, context),
    do: {:ok, Keyword.get(context, :state).judgements, []}

  def mock(:valid_header_markers?, _), do: true

  defimpl Encodable do
    alias Codec.VariableSize
    # E(↕[x^x ∈ ψg],↕[x^x ∈ ψb],↕[x^x ∈ ψw],↕[x^x ∈ ψo])
    # TODO : convert each mapset into sorted array
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
