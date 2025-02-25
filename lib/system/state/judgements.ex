defmodule System.State.Judgements do
  @moduledoc """
  Formula (10.1) v0.6.2
  """
  alias Block.Extrinsic.Disputes
  alias Block.Extrinsic.Disputes.{Error, Verdict}
  alias Block.Header
  alias System.State.Judgements
  use SelectiveMock
  use MapUnion

  @type t :: %__MODULE__{
          # g
          good: MapSet.t(Types.hash()),
          # b
          bad: MapSet.t(Types.hash()),
          # w
          wonky: MapSet.t(Types.hash()),
          # o
          offenders: MapSet.t(Types.ed25519_key())
        }

  # Formula (10.1) v0.6.0
  defstruct good: MapSet.new(),
            bad: MapSet.new(),
            wonky: MapSet.new(),
            offenders: MapSet.new()

  mockable transition(%Header{} = header, disputes, state) do
    # Formula (10.11) v0.6.0
    # Formula (10.12) v0.6.0
    case calculate_v(disputes, state) do
      {:ok, v} ->
        bad_wonky_verdicts =
          for {hash, sum, validator_count} <- v,
              sum != div(2 * validator_count, 3) + 1,
              do: hash

        # Formula (10.19) v0.6.0
        new_offenders = for %{key: k} <- disputes.culprits ++ disputes.faults, do: k

        if valid_header_markers?(header, new_offenders) do
          {:ok,
           %Judgements{
             posterior_judgement_sets(v, state.judgements)
             | offenders: state.judgements.offenders ++ MapSet.new(new_offenders)
           }, bad_wonky_verdicts}
        else
          {:error, Error.invalid_header_markers()}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def calculate_v(%Disputes{verdicts: verdicts, culprits: c, faults: f}, state) do
    current_epoch = Util.Time.epoch_index(state.timeslot)

    v_set =
      for verdict <- verdicts do
        validator_set =
          Disputes.get_validator_set(
            state.curr_validators,
            state.prev_validators,
            current_epoch,
            verdict.epoch_index
          )

        {verdict.work_report_hash, Verdict.sum_judgements(verdict), length(validator_set)}
      end

    issues =
      Enum.reduce(v_set, {false, false}, fn {r, sum, v_count}, {culprits_issue, faults_issue} ->
        # Formula (10.14) v0.6.0
        new_culprits_issue =
          culprits_issue or (sum == 0 && length(Enum.filter(c, &(&1.work_report_hash == r))) < 2)

        # Formula (10.13) v0.6.0
        new_faults_issue =
          faults_issue or
            (sum == div(2 * v_count, 3) + 1 &&
               Enum.empty?(Enum.filter(f, &(&1.work_report_hash == r))))

        {new_culprits_issue, new_faults_issue}
      end)

    case issues do
      {true, _} ->
        {:error, Error.not_enough_culprits()}

      {_, true} ->
        {:error, Error.not_enough_faults()}

      _ ->
        {:ok, v_set}
    end
  end

  # Formula (10.20) v0.6.0
  mockable(
    valid_header_markers?(
      %Header{offenders_marker: of},
      new_offenders
    ),
    do: of == new_offenders
  )

  defp posterior_judgement_sets(v, judgements) do
    Enum.reduce(v, judgements, fn {hash, sum, validator_count}, acc ->
      cond do
        # Formula (10.16) v0.6.0
        sum == div(2 * validator_count, 3) + 1 ->
          %{acc | good: MapSet.put(acc.good, hash)}

        # Formula (10.17) v0.6.0
        sum == 0 ->
          %{acc | bad: MapSet.put(acc.bad, hash)}

        # Formula (10.18) v0.6.0
        sum == div(validator_count, 3) ->
          %{acc | wonky: MapSet.put(acc.wonky, hash)}
      end
    end)
  end

  def union_all(%__MODULE__{good: g, bad: b, wonky: w}) do
    g ++ b ++ w
  end

  def mock(:transition, context),
    do: {:ok, Keyword.get(context, :state).judgements, []}

  def mock(:valid_header_markers?, _), do: true

  defimpl Encodable do
    use Codec.Encoder
    # E(↕[x^x ∈ ψg],↕[x^x ∈ ψb],↕[x^x ∈ ψw],↕[x^x ∈ ψo])
    def encode(%Judgements{} = j) do
      e({sorted_vs(j.good), sorted_vs(j.bad), sorted_vs(j.wonky), sorted_vs(j.offenders)})
    end

    defp sorted_vs(mapset) do
      vs(mapset |> MapSet.to_list() |> Enum.sort())
    end
  end

  use JsonDecoder

  def json_mapping do
    decoder = &(JsonDecoder.from_json(&1) |> MapSet.new())

    %{
      good: [decoder, :psi_g],
      bad: [decoder, :psi_b],
      wonky: [decoder, :psi_w],
      offenders: [decoder, :psi_o]
    }
  end
end
