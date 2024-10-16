defmodule System.State.Ready do
  alias Block.Extrinsic.Guarantee.WorkReport

  @type t :: %__MODULE__{
          work_report: WorkReport.t(),
          dependencies: MapSet.t(Types.hash())
        }

  defstruct work_report: %WorkReport{}, dependencies: MapSet.new()

  @spec to_tuple(t()) :: {WorkReport.t(), MapSet.t(Types.hash())}
  def to_tuple(%__MODULE__{} = ready) do
    {ready.work_report, ready.dependencies}
  end
end
