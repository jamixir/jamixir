defmodule System.State.Ready do
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Codec.VariableSize
  use JsonDecoder

  @type t :: %__MODULE__{
          # w
          work_report: WorkReport.t(),
          # d
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

  def to_json_mapping, do: %{work_report: :report}

  def parse_dependencies(deps) do
    MapSet.new(for d <- deps, do: JsonDecoder.from_json(d))
  end

  defimpl Encodable do
    alias System.State.Ready
    use Codec.Encoder

    # Formula (C.13) v0.6.5
    def encode(%Ready{work_report: w, dependencies: d}), do: e({w, vs(d)})
  end

  use Sizes

  def decode(bin) do
    {work_report, rest} = WorkReport.decode(bin)
    {dependencies, rest} = VariableSize.decode(rest, :mapset, @hash_size)
    {%__MODULE__{work_report: work_report, dependencies: dependencies}, rest}
  end
end
