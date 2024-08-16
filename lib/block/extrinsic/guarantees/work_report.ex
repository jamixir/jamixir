defmodule Block.Extrinsic.Guarantee.WorkReport do
  @moduledoc """
  Work report
  section 11.1
  """
  alias Block.Extrinsic.Guarantee.{WorkResult, AvailabilitySpecification, WorkReport}
  alias Block.Extrinsic.Availability
  # Formula (119) v0.3.4
  @type t :: %__MODULE__{
          # s
          specification: Availability.t(),
          # x
          refinement_context: RefinementContext.t(),
          # c
          core_index: non_neg_integer(),
          # a
          authorizer_hash: Types.hash(),
          # o
          output: binary(),
          # r
          work_results: list(WorkResult.t())
        }

  # Formula (119) v0.3.4
  defstruct specification: {},
            refinement_context: %RefinementContext{},
            core_index: 0,
            authorizer_hash: <<0::256>>,
            output: "",
            work_results: []

  defimpl Encodable do
    alias Codec.VariableSize
    # Formula (286) v0.3.4
    def encode(%WorkReport{} = wr) do
      Codec.Encoder.encode({
        wr.authorizer_hash,
        wr.core_index,
        VariableSize.new(wr.output),
        wr.refinement_context,
        wr.specification,
        VariableSize.new(wr.work_results)
      })
    end
  end
end
