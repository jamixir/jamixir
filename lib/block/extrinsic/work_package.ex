defmodule Block.Extrinsic.WorkPackage do
  @moduledoc """
  Defines a WorkPackage struct and its types.
  """
  alias Block.Extrinsic.WorkItem

  @type t :: %__MODULE__{
          # j
          authorization_token: binary(),
          # h
          service_index: integer(),
          # c
          authorization_code_hash: binary(),
          # p
          parameterization_blob: binary(),
          # x
          context: RefinementContext.t(),
          # i
          work_items: list(WorkItem.t())
        }

  # Formula (176) v0.3.4
  defstruct [
    # j
    authorization_token: <<>>,
    # h
    service_index: 0,
    # c
    authorization_code_hash: <<>>,
    # p
    parameterization_blob: <<>>,
    # x
    context: %RefinementContext{},
    # i
    work_items: []
  ]

  defimpl Encodable do
    alias Block.Extrinsic.WorkPackage
    alias Codec.{VariableSize, Encoder}
    # Formula (287) v0.3.4
    def encode(%WorkPackage{} = wp) do
      Encoder.encode({
        VariableSize.new(wp.authorization_token),
        Encoder.encode_le(wp.service_index, 4),
        wp.authorization_code_hash,
        VariableSize.new(wp.parameterization_blob),
        wp.context,
        VariableSize.new(wp.work_items)
      })
    end
  end
end
