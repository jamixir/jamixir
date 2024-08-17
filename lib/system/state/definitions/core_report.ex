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
end
