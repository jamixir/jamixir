defmodule Block.Extrinsic.Guarantee.WorkResult do
  @moduledoc """
  Formula (11.6) v0.6.3
  """
  alias Codec.VariableSize
  alias Block.Extrinsic.{Guarantee.WorkExecutionError, WorkItem}
  alias Util.Hash
  use Codec.Encoder

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
          result: {:ok, binary()} | {:error, WorkExecutionError.t()}
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
            result: {:ok, <<>>}

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
    # Formula (C.23) v0.6.2
    def encode(%WorkResult{} = wr) do
      e_le(wr.service, 4) <>
        e({wr.code_hash, wr.payload_hash}) <>
        e_le(wr.gas_ratio, 8) <>
        do_encode(wr.result)
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

  use Sizes
  use Codec.Decoder

  def decode(bin) do
    <<service::service(), code_hash::binary-size(@hash_size),
      payload_hash::binary-size(@hash_size), gas_ratio::64-little, error_code::8,
      temp_rest::binary>> = bin

    {result, rest} =
      case error_code do
        0 ->
          {result, rest} = VariableSize.decode(temp_rest, :binary)
          {{:ok, result}, rest}

        _ ->
          code = WorkExecutionError.code_name(error_code)
          {{:error, code}, temp_rest}
      end

    {%__MODULE__{
       service: service,
       code_hash: code_hash,
       payload_hash: payload_hash,
       gas_ratio: gas_ratio,
       result: result
     }, rest}
  end

  use JsonDecoder

  def json_mapping,
    do: %{service: :service_id, gas_ratio: :accumulate_gas, result: &parse_result/1}

  def to_json_mapping,
    do: %{service: :service_id, gas_ratio: :accumulate_gas, result: {:result, &result_to_json/1}}

  def parse_result(%{ok: ok}), do: {:ok, JsonDecoder.from_json(ok)}
  def parse_result(%{panic: _}), do: {:error, :panic}

  def result_to_json({:ok, b}), do: %{ok: b}
  def result_to_json({:error, e}), do: %{e => nil}
end
