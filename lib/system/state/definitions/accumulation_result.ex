defmodule System.AccumulationResult do
  alias System.DeferredTransfer

  @type t :: %__MODULE__{
          state: t(),
          transfers: list(DeferredTransfer.t()),
          output: Types.hash() | nil,
          gas_used: non_neg_integer()
        }
  defstruct [:state, :transfers, :output, :gas_used]
end
