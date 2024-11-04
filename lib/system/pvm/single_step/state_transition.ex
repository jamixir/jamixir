defmodule System.PVM.SingleStep.StateTransition do
  alias System.PVM.SingleStep.{CallParams, Result}

  # Formula (241) v0.4.5
  # Ψ1
  @spec step(CallParams.t()) :: Result.t()
  def step(%CallParams{} = _params) do
    # TODO

    %Result{}
  end
end
