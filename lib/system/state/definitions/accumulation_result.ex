defmodule System.AccumulationResult do
  alias System.State.Accumulation
  alias System.DeferredTransfer

  @type t :: %__MODULE__{
          # o
          state: Accumulation.t(),
          # t
          transfers: list(DeferredTransfer.t()),
          # b
          output: Types.hash() | nil,
          # u
          gas_used: non_neg_integer(),
          # p
          preimages: list({Types.service_index(), binary()})
        }
  defstruct state: %Accumulation{}, transfers: [], output: nil, gas_used: 0, preimages: []

  def new({state, transfers, output, gas_used, preimages}) do
    %__MODULE__{
      state: state,
      transfers: transfers,
      output: output,
      gas_used: gas_used,
      preimages: preimages
    }
  end
end
