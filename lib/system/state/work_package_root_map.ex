defmodule System.State.WorkPackageRootMap do
  alias Block.Extrinsic.Guarantee.WorkReport
  @type t :: %{Types.hash() => Types.hash()}

  # Formula (166) v0.4.1
  @spec create(list(WorkReport.t())) :: t()
  def create(work_reports) do
    for %{specification: ws} <- work_reports,
        into: %{},
        do: {ws.work_package_hash, ws.exports_root}
  end

  @spec initial_state() :: list(t())
  def initial_state, do: List.duplicate(%{}, Constants.epoch_length())
end
