defmodule PVM.Accumulate.Operand do
  alias Block.Extrinsic.Guarantee.WorkExecutionError
  alias Types

  # Formula (12.18) v0.5.2
  @type t :: %__MODULE__{
          o: binary() | WorkExecutionError.t(),
          l: Types.hash(),
          k: Types.hash(),
          a: binary()
        }

  defstruct [:o, :l, :k, :a]
end
