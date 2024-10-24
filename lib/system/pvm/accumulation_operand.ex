defmodule System.PVM.AccumulationOperand do
  alias Block.Extrinsic.Guarantee.WorkExecutionError
  alias Types

  # Formula (174) v0.4.1
  @type t :: %__MODULE__{
          o: binary() | WorkExecutionError.t(),
          l: Types.hash(),
          k: Types.hash(),
          a: binary()
        }

  defstruct [:o, :l, :k, :a]
end
