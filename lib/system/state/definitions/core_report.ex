defmodule System.State.CoreReport do
  @moduledoc """
  Formula (11.1) v0.6.5
  """

  alias Block.Extrinsic.Guarantee.WorkReport
  alias System.State.CoreReport
  use SelectiveMock
  use Codec.Encoder

  @type t :: %__MODULE__{work_report: WorkReport.t(), timeslot: Types.timeslot()}

  defstruct work_report: %WorkReport{}, timeslot: 0
  def initial_core_reports, do: for(_ <- 1..Constants.core_count(), do: nil)

  # Formula (10.15) v0.6.5
  def process_disputes(core_reports, bad_wonky_verdicts) do
    for c <- core_reports do
      process_report(c, MapSet.new(bad_wonky_verdicts))
    end
  end

  defp process_report(nil, _bad_wonky_set), do: nil

  defp process_report(core_report, bad_wonky_set) do
    work_results_hash = h(e(core_report.work_report))
    if work_results_hash in bad_wonky_set, do: nil, else: core_report
  end

  @doc """
  Processes availability and updates the core reports accordingly.
  """
  # ρ‡ Formula (4.13) v0.6.5
  mockable process_availability(
             core_reports,
             core_reports_intermediate_1,
             available_work_reports,
             h_t
           ) do
    w = MapSet.new(available_work_reports)

    # Formula (11.17) v0.6.5
    for {cr, intermediate} <- Enum.zip(core_reports, core_reports_intermediate_1) do
      if cr == nil or intermediate == nil,
        do: nil,
        else:
          if(
            cr.work_report in w or
              h_t >= intermediate.timeslot + Constants.unavailability_period(),
            do: nil,
            else: intermediate
          )
    end
  end

  def mock(:process_availability, context) do
    Keyword.get(context, :core_reports)
  end

  @doc """
  Updates core reports with guarantees and current validators.
  """
  def transition(core_reports_2, guarantees, timeslot_) do
    # Formula (11.43) v0.6.5
    for index <- 0..(Constants.core_count() - 1) do
      case Enum.find(guarantees, &(&1.work_report.core_index == index)) do
        nil -> Enum.at(core_reports_2, index)
        w -> %CoreReport{work_report: w.work_report, timeslot: timeslot_}
      end
    end
  end

  defimpl Encodable do
    alias System.State.CoreReport
    use Codec.Encoder
    # Formula (D.2) v0.6.5
    # C(10) ↦ E([¿(w, E4(t)) ∣ (w, t) <− ρ]) ,
    def encode(%CoreReport{} = c) do
      e({c.work_report, t(c.timeslot)})
    end
  end

  use JsonDecoder

  def json_mapping do
    %{
      work_report: %{m: WorkReport, f: :report},
      timeslot: :timeout
    }
  end

  def to_json_mapping,
    do: %{work_report: :report, timeslot: :timeout}
end
