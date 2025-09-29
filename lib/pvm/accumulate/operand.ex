defmodule PVM.Accumulate.Operand do
  alias Block.Extrinsic.Guarantee.WorkExecutionError
  alias Types
  alias Util.Hash

  # Formula (12.13) v0.7.2 - U
  @type t :: %__MODULE__{
          # p
          package_hash: Types.hash(),
          # e
          segment_root: Types.hash(),
          # a
          authorizer: Types.hash(),
          # y
          payload_hash: Types.hash(),
          # g
          gas_limit: Types.gas(),
          # t
          output: binary(),
          # l
          data: {:ok, binary()} | {:error, WorkExecutionError.t()}
        }

  defstruct package_hash: Hash.zero(),
            segment_root: Hash.zero(),
            authorizer: Hash.zero(),
            payload_hash: Hash.zero(),
            gas_limit: 0,
            output: <<>>,
            data: <<>>

  defimpl Encodable do
    alias Block.Extrinsic.Guarantee.WorkDigest
    import Codec.Encoder

    # Formula (C.32) v0.7.2
    def encode(%PVM.Accumulate.Operand{} = o),
      do:
        e({o.package_hash, o.segment_root, o.authorizer, o.payload_hash, o.gas_limit}) <>
          WorkDigest.encode_result(o.data) <> e(vs(o.output))
  end
end
