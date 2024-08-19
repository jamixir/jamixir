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
