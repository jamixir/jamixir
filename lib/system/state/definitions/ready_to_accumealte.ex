defmodule System.State.Ready do
  alias Block.Extrinsic.Guarantee.WorkReport

  @type t :: %__MODULE__{
          work_report: WorkReport.t(),
          dependencies: MapSet.t(Types.hash())
        }

  defstruct work_report: %WorkReport{}, dependencies: MapSet.new()
end
