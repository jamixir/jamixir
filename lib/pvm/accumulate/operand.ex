defmodule PVM.Accumulate.Operand do
  alias Block.Extrinsic.Guarantee.WorkDigest
  alias Block.Extrinsic.Guarantee.WorkExecutionError
  alias Codec.VariableSize
  alias Types
  alias Util.Hash
  import Codec.Encoder
  import Codec.Decoder

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
    alias Codec.VariableSize
    import Codec.Encoder

    # Formula (C.32) v0.7.2
    def encode(%PVM.Accumulate.Operand{} = o),
      # prefix with 0 Formula (C.33)
      do:
        <<0>> <>
          e({o.package_hash, o.segment_root, o.authorizer, o.payload_hash, o.gas_limit}) <>
          WorkDigest.encode_result(o.data) <> e(vs(o.output))
  end

  def decode(bin) do
    <<_::8, package_hash::b(hash), segment_root::b(hash), authorizer::b(hash),
      payload_hash::b(hash), rest::binary>> = bin

    {gas_limit, rest} = de_i(rest)
    <<error_code::8, rest::binary>> = rest

    {data, rest} = WorkDigest.decode_result(error_code, rest)
    {output, rest} = VariableSize.decode(rest, :binary)

    {%PVM.Accumulate.Operand{
       package_hash: package_hash,
       segment_root: segment_root,
       authorizer: authorizer,
       payload_hash: payload_hash,
       gas_limit: gas_limit,
       data: data,
       output: output
     }, rest}
  end
end
