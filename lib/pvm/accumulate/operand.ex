defmodule PVM.Accumulate.Operand do
  alias Util.Hash
  alias Block.Extrinsic.Guarantee.WorkExecutionError
  alias Types

  # Formula (12.19) v0.6.6
  @type t :: %__MODULE__{
          # h
          package_hash: Types.hash(),
          # e
          segment_root: Types.hash(),
          # a
          authorizer: Types.hash(),
          # y
          payload_hash: Types.hash(),
          # g
          gas_limit: Types.gas(),
          # d
          data: {:ok, binary()} | {:error, WorkExecutionError.t()},
          # o
          output: binary()
        }

  defstruct package_hash: Hash.zero(),
            segment_root: Hash.zero(),
            authorizer: Hash.zero(),
            payload_hash: Hash.zero(),
            gas_limit: 0,
            data: <<>>,
            output: <<>>

  defimpl Encodable do
    alias Block.Extrinsic.Guarantee.WorkDigest
    import Codec.Encoder

    # Formula (C.29) v0.6.7
    def encode(%PVM.Accumulate.Operand{} = o),
      do:
        e({o.package_hash, o.segment_root, o.authorizer, o.payload_hash, o.gas_limit}) <>
          WorkDigest.encode_result(o.data) <> e(vs(o.output))
  end
end
