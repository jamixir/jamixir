defmodule PVM.RefineParams do
  alias Util.Hash

  @type t :: %__MODULE__{
          # c
          service_code: Types.hash(),
          # g
          gas: Types.gas(),
          # s
          service: Types.service_index(),
          # p
          work_package_hash: Types.hash(),
          # y
          payload: binary(),
          # c
          refinement_context: RefinementContext.t(),
          # a
          authorizer_hash: binary(),
          # o
          output: binary(),
          # i
          import_segments: list(Types.export_segment()),
          # x
          extrinsic_data: list(binary()),
          # ς
          export_offset: non_neg_integer()
        }
  defstruct [
    # c
    service_code: Hash.zero(),
    # g
    gas: 0,
    # s
    service: 0,
    # p
    work_package_hash: Hash.zero(),
    # y
    payload: <<>>,
    # c
    refinement_context: %RefinementContext{},
    # a
    authorizer_hash: <<>>,
    # o
    output: Hash.zero(),
    # i
    import_segments: [],
    # x
    extrinsic_data: [],
    # ς
    export_offset: 0
  ]
end
