defmodule System.State.CoreReport do
  @moduledoc """
  Formula (118) v0.3.4
  Represents the state of a core's report, including the work report and the timeslot it was reported.
  """

  alias Block.Extrinsic.Guarantee.WorkReport

  @type t :: %__MODULE__{
          work_report: WorkReport.t(),
          timeslot: Types.timeslot()
        }

  defstruct work_report: %WorkReport{}, timeslot: 0
  def initial_core_reports, do: 1..Constants.core_count() |> Enum.map(fn _ -> nil end)

  @doc """
  Processes disputes and updates the core reports accordingly.
  """
  def process_disputes(_core_reports, _disputes) do
    # TODO: Implement the logic to process disputes
  end

  @doc """
  Processes availability and updates the core reports accordingly.
  """
  def process_availability(_core_reports, _availability) do
    # TODO: Implement the logic to process availability
  end

  @doc """
  Updates core reports with guarantees and current validators.
  """
  def posterior_core_reports(core_reports, guarantees, _curr_validators, _new_timeslot) do
    # Formula (120) v0.3.4
    # ∀w ∈ W ∶ ∣E(w)∣ ≤ WR
    cond do
      !Enum.all?(guarantees, &WorkReport.valid_size?(&1.work_report)) ->
        {:error, :invalid_work_report_size}

      # Add other checks here
      true ->
        {:ok, core_reports}
    end
  end

  defimpl Encodable do
    alias System.State.CoreReport
    # Formula (292) v0.3.4
    # C(10) ↦ E([¿(w, E4(t)) ∣ (w, t) <− ρ]) ,
    def encode(%CoreReport{} = c) do
      Codec.Encoder.encode({
        c.work_report,
        Codec.Encoder.encode_le(c.timeslot, 4)
      })
    end
  end
end
