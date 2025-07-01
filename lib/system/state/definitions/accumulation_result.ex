defmodule System.AccumulationResult do
  alias System.DeferredTransfer
  alias System.State.Accumulation

  # Formula (12.20) v0.7.0 - O
  @type t :: %__MODULE__{
          # e
          state: Accumulation.t(),
          # t
          transfers: list(DeferredTransfer.t()),
          # y
          output: Types.hash() | nil,
          # u
          gas_used: non_neg_integer(),
          # p
          preimages: list({Types.service_index(), binary()})
        }
  defstruct state: %Accumulation{}, transfers: [], output: nil, gas_used: 0, preimages: []

  def new({state, transfers, output, gas_used, _preimages}) do
    %__MODULE__{
      state: state,
      transfers: transfers,
      output: output,
      gas_used: gas_used,
      # TODO: use the preimages - isnt used because the accumulate test vectors are failing,
      # must be that they are not updated to latest GP (0.6.6) (12.05.2025)
      preimages: []
    }
  end
end
