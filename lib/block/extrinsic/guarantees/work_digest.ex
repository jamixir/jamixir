defmodule Block.Extrinsic.Guarantee.WorkDigest do
  @moduledoc """
  Formula (11.6) v0.6.6
  """
  alias Codec.VariableSize
  alias Block.Extrinsic.{Guarantee.WorkExecutionError, WorkItem}
  alias Util.Hash
  use Codec.{Decoder, Encoder}

  @type error :: :out_of_gas | :unexpected_termination | :bad_code | :code_too_large

  @type t :: %__MODULE__{
          # s
          service: non_neg_integer(),
          # c
          code_hash: Types.hash(),
          # y
          payload_hash: Types.hash(),
          # g
          gas_ratio: non_neg_integer(),
          # d
          result: {:ok, binary()} | {:error, WorkExecutionError.t()},
          # u
          gas_used: Types.gas(),
          # i
          imports: non_neg_integer(),
          # e
          exports: non_neg_integer(),
          # x
          extrinsic_count: non_neg_integer(),
          # z
          extrinsic_size: non_neg_integer()
        }

  # s
  defstruct service: 0,
            # c
            code_hash: Hash.zero(),
            # y
            payload_hash: Hash.zero(),
            # g
            gas_ratio: 0,
            # d
            result: {:ok, <<>>},
            # u
            gas_used: 0,
            # i
            imports: 0,
            # e
            exports: 0,
            # x
            extrinsic_count: 0,
            # z
            extrinsic_size: 0

  @spec new(WorkItem.t(), {:ok, binary()} | {:error, WorkExecutionError.t()}) :: t
  def new(%WorkItem{} = wi, output) do
    %__MODULE__{
      service: wi.service,
      code_hash: wi.code_hash,
      payload_hash: h(wi.payload),
      gas_ratio: wi.refine_gas_limit,
      result: output
    }
  end

  defimpl Encodable do
    alias Block.Extrinsic.Guarantee.{WorkExecutionError, WorkDigest}
    use Codec.Encoder
    # Formula (C.23) v0.6.5
    # E(x∈L) ≡ E(E4(xs),xc,xy ,E8(xg ),O(xd),xu,xi,xx,xz ,xe)
    @spec encode(Block.Extrinsic.Guarantee.WorkDigest.t()) :: <<_::32, _::_*8>>
    def encode(%WorkDigest{} = wd) do
      t(wd.service) <>
        e({wd.code_hash, wd.payload_hash}) <>
        t(wd.gas_ratio) <>
        WorkDigest.encode_result(wd.result) <>
        e({
          wd.gas_used,
          wd.imports,
          wd.extrinsic_count,
          wd.extrinsic_size,
          wd.exports
        })
    end
  end

  # Formula (C.30) v0.6.5
  def encode_result({:ok, b}) do
    e({0, vs(b)})
  end

  # Formula (C.30) v0.6.5
  def encode_result({:error, e}) do
    e(WorkExecutionError.code(e))
  end

  def decode(bin) do
    <<service::service(), code_hash::b(hash), payload_hash::b(hash), gas_ratio::m(gas),
      error_code::8, temp_rest::binary>> = bin

    {result, rest} =
      case error_code do
        0 ->
          {result, rest} = VariableSize.decode(temp_rest, :binary)
          {{:ok, result}, rest}

        _ ->
          code = WorkExecutionError.code_name(error_code)
          {{:error, code}, temp_rest}
      end

    {refine_gas, rest} = de_i(rest)
    {imports, rest} = de_i(rest)
    {extrinsic_count, rest} = de_i(rest)
    {extrinsic_size, rest} = de_i(rest)
    {exports, rest} = de_i(rest)

    {%__MODULE__{
       service: service,
       code_hash: code_hash,
       payload_hash: payload_hash,
       gas_ratio: gas_ratio,
       result: result,
       gas_used: refine_gas,
       imports: imports,
       extrinsic_count: extrinsic_count,
       extrinsic_size: extrinsic_size,
       exports: exports
     }, rest}
  end

  use JsonDecoder

  def json_mapping,
    do: %{
      service: :service_id,
      gas_ratio: :accumulate_gas,
      result: &parse_result/1,
      exports: [fn v -> v.exports end, :refine_load],
      extrinsic_count: [fn v -> v.extrinsic_count end, :refine_load],
      extrinsic_size: [fn v -> v.extrinsic_size end, :refine_load],
      imports: [fn v -> v.imports end, :refine_load],
      gas_used: [fn v -> v.gas_used end, :refine_load]
    }

  def value_or_zero(v), do: v || 0

  def to_json_mapping,
    do: %{service: :service_id, gas_ratio: :accumulate_gas, result: {:result, &result_to_json/1}}

  def parse_result(%{ok: ok}), do: {:ok, JsonDecoder.from_json(ok)}
  def parse_result(%{panic: _}), do: {:error, :panic}

  def result_to_json({:ok, b}), do: %{ok: b}
  def result_to_json({:error, e}), do: %{e => nil}
end
