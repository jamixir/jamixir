defmodule PVM.Accumulate.Operand do
  alias Block.Extrinsic.Guarantee.WorkExecutionError
  alias Types

  # Formula (12.18) v0.6.3
  @type t :: %__MODULE__{
          h: Types.hash(),
          e: Types.hash(),
          a: Types.hash(),
          o: binary(),
          y: Types.hash(),
          d: {:ok, binary()} | {:error, WorkExecutionError.t()}
        }

  defstruct [:h, :e, :a, :o, :y, :d]

  defimpl Encodable do
    use Codec.Encoder
    def encode_d({:ok, bin}) when is_binary(bin), do: e(bin)
    def encode_d({:error, o}), do: e(WorkExecutionError.code(o))

    def encode(%PVM.Accumulate.Operand{} = o), do: e({o.h, o.e, o.a, o.o, o.y}) <> encode_d(o.d)
  end
end
