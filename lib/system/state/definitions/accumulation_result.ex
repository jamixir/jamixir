defmodule System.AccumulationResult do
  alias System.State.Accumulation
  alias System.DeferredTransfer

  @type t :: %__MODULE__{
          state: Accumulation.t(),
          transfers: list(DeferredTransfer.t()),
          output: Types.hash() | nil,
          gas_used: non_neg_integer()
        }
  defstruct state: %Accumulation{}, transfers: [], output: nil, gas_used: 0
end
