defmodule System.State.Ready do
  alias Block.Extrinsic.Guarantee.WorkReport
  use JsonDecoder

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

  def json_mapping do
    %{
      work_report: %{m: WorkReport, f: :report},
      dependencies: &parse_dependencies/1
    }
  end

  def parse_dependencies(deps) do
    MapSet.new(for d <- deps, do: JsonDecoder.from_json(d))
  end
end
