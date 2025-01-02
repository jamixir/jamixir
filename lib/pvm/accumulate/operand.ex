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

  defimpl Encodable do
    use Codec.Encoder
    def encode_o(o) when is_binary(o), do: e(o)
    def encode_o(o), do: e(WorkExecutionError.code(o))

    def encode(%PVM.Accumulate.Operand{} = o) do
      encode_o(o.o) <> e(o.l) <> e(o.k) <> e(o.a)
    end
  end
end
