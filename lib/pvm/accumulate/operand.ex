defmodule PVM.Accumulate.Operand do
  alias Util.Hash
  alias Block.Extrinsic.Guarantee.WorkExecutionError
  alias Types

  # Formula (12.18) v0.6.4
  @type t :: %__MODULE__{
          h: Types.hash(),
          e: Types.hash(),
          a: Types.hash(),
          o: binary(),
          y: Types.hash(),
          d: {:ok, binary()} | {:error, WorkExecutionError.t()}
        }

  defstruct h: Hash.zero(), e: Hash.zero(), a: Hash.zero(), o: <<>>, y: Hash.zero(), d: <<>>

  defimpl Encodable do
    alias Block.Extrinsic.Guarantee.WorkResult
    use Codec.Encoder

    # Formula (C.29) v0.6.4
    def encode(%PVM.Accumulate.Operand{} = o),
      do: e({o.h, o.e, o.a, vs(o.o), o.y}) <> WorkResult.encode_result(o.d)
  end
end
