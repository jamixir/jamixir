defmodule System.State.CoreReport do
  @moduledoc """
  Formula (117) v0.4.5
  Represents the state of a core's report, including the work report and the timeslot it was reported.
  """

  alias Block.Extrinsic.AvailabilitySpecification
  alias System.State.CoreReport
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Codec.Encoder
  alias Util.Hash
  use SelectiveMock

  @type t :: %__MODULE__{work_report: WorkReport.t(), timeslot: Types.timeslot()}

  defstruct work_report: %WorkReport{}, timeslot: 0
  def initial_core_reports, do: for(_ <- 1..Constants.core_count(), do: nil)

  # Formula (111) v0.4.5
  def process_disputes(core_reports, bad_wonky_verdicts) do
    for c <- core_reports do
      process_report(c, MapSet.new(bad_wonky_verdicts))
    end
  end

  defp process_report(nil, _bad_wonky_set), do: nil

  defp process_report(core_report, bad_wonky_set) do
    work_results_hash = Hash.default(Encoder.encode(core_report.work_report))
    if work_results_hash in bad_wonky_set, do: nil, else: core_report
  end

  @doc """
  Processes availability and updates the core reports accordingly.
  """
  # ρ‡ Formula (26) v0.4.5
  mockable process_availability(core_reports, core_reports_intermediate_1, assurances) do
    w = WorkReport.available_work_reports(assurances, core_reports_intermediate_1) |> MapSet.new()

    # Formula (131) v0.4.5
    for {cr, intermediate} <- Enum.zip(core_reports, core_reports_intermediate_1) do
      if cr.work_report in w, do: nil, else: intermediate
    end
  end

  def mock(:process_availability, context) do
    Keyword.get(context, :core_reports)
  end

  @doc """
  Updates core reports with guarantees and current validators.
  """
  def calculate_core_reports_(core_reports_2, guarantees, timeslot_) do
    # Formula (157) v0.4.5
    Enum.with_index(core_reports_2, fn cr, index ->
      case Enum.find(guarantees, &(&1.work_report.core_index == index)) do
        nil -> cr
        w -> %CoreReport{work_report: w.work_report, timeslot: timeslot_}
      end
    end)
  end

  defimpl Encodable do
    alias System.State.CoreReport
    use Codec.Encoder
    # Formula (321) v0.4.5
    # C(10) ↦ E([¿(w, E4(t)) ∣ (w, t) <− ρ]) ,
    # TODO: fix missing NilDiscriminator
    def encode(%CoreReport{} = c) do
      e({c.work_report, e_le(c.timeslot, 4)})
    end
  end

  use JsonDecoder

  def json_mapping do
    %{
      work_report: [
        fn wph ->
          hash = JsonDecoder.from_json(wph)

          %WorkReport{
            specification: %AvailabilitySpecification{
              work_package_hash: hash
            }
          }
        end,
        :dummy_work_report
      ],
      timeslot: :timeout
    }
  end

  # Formula (151) v0.4.5
  @spec a(list(t())) :: MapSet.t(Types.hash())
  def a(core_reports) do
    for i <- core_reports,
        i != nil,
        p = i.work_report.refinement_context.prerequisite,
        p != nil,
        into: MapSet.new(),
        do: p
  end
end
