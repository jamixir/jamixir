defmodule Block.Extrinsic.Guarantee.WorkReport do
  @moduledoc """
  Work report
  section 11.1
  """
  alias Block.Extrinsic.Guarantee.{WorkResult, AvailabilitySpecification, WorkReport}

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
          # r
          work_results: list(WorkResult.t())
        }

  # Formula (119) v0.3.4
  defstruct specification: {}, # s
            refinement_context: {}, # x
            core_index: 0, # c
            authorizer_hash: <<0::256>>, # a
            output: "", # o
            work_results: [] # r

  def new(specification, refinement_context, core_index, authorizer_hash, output, work_results) do
    %WorkReport{
      specification: specification,
      refinement_context: refinement_context,
      core_index: core_index,
      authorizer_hash: authorizer_hash,
      output: output,
      work_results: work_results
    }
  end
end
