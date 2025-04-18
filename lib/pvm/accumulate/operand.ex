defmodule PVM.Accumulate.Operand do
  alias Util.Hash
  alias Block.Extrinsic.Guarantee.WorkExecutionError
  alias Types

  # Formula (12.18) v0.6.5
  @type t :: %__MODULE__{
          # h
          package_hash: Types.hash(),
          # e
          segment_root: Types.hash(),
          # a
          authorizer: Types.hash(),
          # o
          output: binary(),
          # y
          payload_hash: Types.hash(),
          # g
          gas_limit: Types.gas(),
          # d
          data: {:ok, binary()} | {:error, WorkExecutionError.t()}
        }

  defstruct package_hash: Hash.zero(),
            segment_root: Hash.zero(),
            authorizer: Hash.zero(),
            output: <<>>,
            payload_hash: Hash.zero(),
            gas_limit: 0,
            data: <<>>

  defimpl Encodable do
    alias Block.Extrinsic.Guarantee.WorkResult
    use Codec.Encoder

    #  \se(t¬payloadhash, x_\ot¬gaslimit, O(x_\ot¬data)) \\

    # Formula (C.29) v0.6.5
    def encode(%PVM.Accumulate.Operand{} = o),
      do:
        e(
          {o.package_hash, o.segment_root, o.authorizer, vs(o.output), o.payload_hash,
           o.gas_limit}
        ) <> WorkResult.encode_result(o.data)
  end
end
