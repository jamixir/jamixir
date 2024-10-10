defmodule System.State.CoreReport do
  @moduledoc """
  Formula (117) v0.4.1
  Represents the state of a core's report, including the work report and the timeslot it was reported.
  """

  alias System.State.CoreReport
  alias Block.Extrinsic.Assurance
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Codec.Encoder
  alias Util.Hash
  use SelectiveMock

  @type t :: %__MODULE__{work_report: WorkReport.t(), timeslot: Types.timeslot()}

  defstruct work_report: %WorkReport{}, timeslot: 0
  def initial_core_reports, do: 1..Constants.core_count() |> Enum.map(fn _ -> nil end)

  # Formula (111) v0.4.1
  def process_disputes(core_reports, bad_wonky_verdicts) do
    bad_wonky_set = MapSet.new(bad_wonky_verdicts)
    Enum.map(core_reports, &process_report(&1, bad_wonky_set))
  end

  defp process_report(nil, _bad_wonky_set), do: nil

  defp process_report(core_report, bad_wonky_set) do
    work_results_hash = Hash.default(Encoder.encode(core_report.work_report))
    if MapSet.member?(bad_wonky_set, work_results_hash), do: nil, else: core_report
  end

  @doc """
  Processes availability and updates the core reports accordingly.
  """
  # ρ‡ Formula (26) v0.4.1
  mockable process_availability(core_reports, core_reports_intermediate_1, assurances) do
    w =
      Assurance.available_work_reports(assurances, core_reports_intermediate_1)
      |> MapSet.new()

    # Formula (131) v0.4.1
    Enum.zip(core_reports, core_reports_intermediate_1)
    |> Enum.map(fn
      {cr, intermediate} ->
        if MapSet.member?(w, cr.work_report),
          do: nil,
          else: intermediate
    end)
  end

  def mock(:process_availability, context) do
    Keyword.get(context, :core_reports)
  end

  @doc """
  Updates core reports with guarantees and current validators.
  """
  def calculate_core_reports_(core_reports_2, guarantees, timeslot_) do
    # Formula (119) v0.4.1
    # ∀w ∈ W ∶ ∣E(w)∣ ≤ WR
    # TODO: add ∣wl ∣ ≤ 8
    if Enum.any?(guarantees, &(!WorkReport.valid_size?(&1.work_report))) do
      {:error, :invalid_work_report_size}
    else
      # Formula (153) v0.4.1
      {:ok,
       Enum.with_index(core_reports_2, fn cr, index ->
         case Enum.find(guarantees, &(&1.work_report.core_index == index)) do
           nil -> cr
           w -> %CoreReport{work_report: w.work_report, timeslot: timeslot_}
         end
       end)}
    end
  end

  defimpl Encodable do
    alias System.State.CoreReport
    # Formula (314) v0.4.1
    # C(10) ↦ E([¿(w, E4(t)) ∣ (w, t) <− ρ]) ,
    #TODO: fix missing NilDiscriminator
    def encode(%CoreReport{} = c) do
      Codec.Encoder.encode({
        c.work_report,
        Codec.Encoder.encode_le(c.timeslot, 4)
      })
    end
  end
end
