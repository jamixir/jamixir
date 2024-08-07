defmodule System.WorkReport do
  alias System.WorkResult

  @type t :: %__MODULE__{
          specfication: AvailabiltySpecification.t(),
          refinemtn_context: RefinementContext.t(),
          core_index: non_neg_integer(),
          authorizer_hash: <<_::256>>,
          output: binary(),
          work_results: list(WorkResult.t())
        }

  defstruct specfication: {},
            refinemtn_context: {},
            core_index: 0,
            authorizer_hash: <<0::256>>,
            output: "",
            work_results: []

  def new(specfication, refinemtn_context, core_index, authorizer_hash, output, work_results) do
    %System.WorkReport{
      specfication: specfication,
      refinemtn_context: refinemtn_context,
      core_index: core_index,
      authorizer_hash: authorizer_hash,
      output: output,
      work_results: work_results
    }
  end
end
