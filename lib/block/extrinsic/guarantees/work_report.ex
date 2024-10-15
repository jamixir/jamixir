defmodule Block.Extrinsic.Guarantee.WorkReport do
  @moduledoc """
  Work report
  section 11.1
  """
  alias Block.Extrinsic.AvailabilitySpecification
  alias Block.Extrinsic.Guarantee.{WorkReport, WorkResult}
  alias Util.Hash

  # Formula (118) v0.4.1
  @type t :: %__MODULE__{
          # s
          specification: AvailabilitySpecification.t(),
          # x
          refinement_context: RefinementContext.t(),
          # c
          core_index: non_neg_integer(),
          # a
          authorizer_hash: Types.hash(),
          # o
          output: binary(),
          # l
          segment_root_lookup: %{Types.hash() => Types.hash()},
          # r
          results: list(WorkResult.t())
        }

  # Formula (118) v0.4.1
  defstruct specification: {},
            refinement_context: %RefinementContext{},
            core_index: 0,
            authorizer_hash: Hash.zero(),
            output: "",
            segment_root_lookup: MapSet.new(),
            results: []

  # Formula (119) v0.4.1

  # ∀w ∈ W ∶ ∣wl ∣ ≤ 8 and ∣E(w)∣ ≤ WR
  @spec valid_size?(WorkReport.t()) :: boolean()
  def valid_size?(%__MODULE__{} = wr) do
    map_size(wr.segment_root_lookup) <= 8 and
      byte_size(Codec.Encoder.encode(wr)) <= Constants.max_work_report_size()
  end

  use JsonDecoder

  def json_mapping do
    %{
      specification: %{m: AvailabilitySpecification, f: :package_spec},
      refinement_context: %{m: RefinementContext, f: :context},
      output: :auth_output,
      results: [WorkResult]
    }
  end

  defimpl Encodable do
    alias Codec.VariableSize
    # Formula (307) v0.4.1
    # E(xs,xx,xc,xa,↕xo,↕xl,↕xr)
    def encode(%WorkReport{} = wr) do
      Codec.Encoder.encode({
        wr.specification,
        wr.refinement_context,
        wr.core_index,
        VariableSize.new(wr.segment_root_lookup),
        wr.authorizer_hash,
        VariableSize.new(wr.output),
        VariableSize.new(wr.results)
      })
    end
  end
end
