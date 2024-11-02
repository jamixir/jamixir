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

  @spec initial_state() :: list(t())
  def initial_state, do: List.duplicate([], Constants.epoch_length())

  # Formula (150) v0.4.5
  @spec q(list(list(t()))) :: MapSet.t(Types.hash())
  def q(ready_to_accumulate) do
    for ready <- List.flatten(ready_to_accumulate),
        p = ready.work_report.refinement_context.prerequisite,
        into: MapSet.new(),
        do: p
  end
end
