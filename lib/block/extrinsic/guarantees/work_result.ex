defmodule Block.Extrinsic.Guarantee.WorkResult do
  @moduledoc """
  Formula (11.6) v0.6.3
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
          refine_gas: Types.gas(),
          # i
          imported_segments: non_neg_integer(),
          # e
          exported_segments: non_neg_integer(),
          # x
          extrinsics_count: non_neg_integer(),
          # z
          extrinsics_size: non_neg_integer()
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
            refine_gas: 0,
            # i
            imported_segments: 0,
            # e
            exported_segments: 0,
            # x
            extrinsics_count: 0,
            # b
            extrinsics_size: 0

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
    alias Block.Extrinsic.Guarantee.{WorkExecutionError, WorkResult}
    use Codec.Encoder
    # Formula (C.23) v0.6.4
    # E(x∈L) ≡ E(E4(xs),xc,xy ,E8(xg ),O(xd),xu,xi,xx,xz ,xe)
    @spec encode(Block.Extrinsic.Guarantee.WorkResult.t()) :: <<_::32, _::_*8>>
    def encode(%WorkResult{} = wr) do
      e(
        {t(wr.service), wr.code_hash, wr.payload_hash, <<wr.gas_ratio::m(gas)>>,
         do_encode(wr.result), wr.refine_gas, wr.imported_segments, wr.extrinsics_count,
         wr.extrinsics_size, wr.exported_segments}
      )
    end

    # Formula (C.29) v0.6.2
    defp do_encode({:ok, b}) do
      e({0, vs(b)})
    end

    # Formula (C.29) v0.6.2
    defp do_encode({:error, e}) do
      e(WorkExecutionError.code(e))
    end
  end

  # Formula (C.30) v0.6.4
  def encode_result({:ok, b}) do
    e({0, vs(b)})
  end

  # Formula (C.30) v0.6.4
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
    {imported_segments, rest} = de_i(rest)
    {extrinsics_count, rest} = de_i(rest)
    {extrinsics_size, rest} = de_i(rest)
    {exported_segments, rest} = de_i(rest)

    {%__MODULE__{
       service: service,
       code_hash: code_hash,
       payload_hash: payload_hash,
       gas_ratio: gas_ratio,
       result: result,
       refine_gas: refine_gas,
       imported_segments: imported_segments,
       extrinsics_count: extrinsics_count,
       extrinsics_size: extrinsics_size,
       exported_segments: exported_segments
     }, rest}
  end

  use JsonDecoder

  def json_mapping,
    do: %{
      service: :service_id,
      gas_ratio: :accumulate_gas,
      result: &parse_result/1,
      exported_segments: &value_or_zero/1,
      extrinsics_count: &value_or_zero/1,
      extrinsics_size: &value_or_zero/1,
      imported_segments: &value_or_zero/1,
      refine_gas: &value_or_zero/1
    }

  def value_or_zero(v), do: v || 0

  def to_json_mapping,
    do: %{service: :service_id, gas_ratio: :accumulate_gas, result: {:result, &result_to_json/1}}

  def parse_result(%{ok: ok}), do: {:ok, JsonDecoder.from_json(ok)}
  def parse_result(%{panic: _}), do: {:error, :panic}

  def result_to_json({:ok, b}), do: %{ok: b}
  def result_to_json({:error, e}), do: %{e => nil}
end
