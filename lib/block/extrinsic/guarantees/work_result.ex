defmodule Block.Extrinsic.Guarantee.WorkResult do
  @moduledoc """
  data conduit by which services’ states
  may be altered through the computation done within a
  work-package

  section 11.1.4
  Formula (122) v0.4.5
  """
  alias Codec.VariableSize
  alias Block.Extrinsic.{Guarantee.WorkExecutionError, WorkItem}
  alias Util.Hash
  use Codec.Encoder

  @type error :: :out_of_gas | :unexpected_termination | :bad_code | :code_too_large

  @type t :: %__MODULE__{
          # s: the index of the service whose state is to be altered and thus whose refine code was already executed
          service: non_neg_integer(),
          # c: hash of the code of the service at the time of being reported
          code_hash: Types.hash(),
          # l: the hash of the payload (l) within the work item which was executed in the
          # refine stage to give this result
          payload_hash: Types.hash(),
          # g: the gas prioritization ratio used when determining how much
          # gas should be allocated to execute this item’s accumulate
          gas_ratio: non_neg_integer(),
          # o: the output or error of the execution of the code, which may be either an
          # octet sequence in case it was successful, or a member of the set J if not
          result: {:ok, binary()} | {:error, WorkExecutionError.t()}
        }

  # s
  defstruct service: 0,
            # c
            code_hash: Hash.zero(),
            # l
            payload_hash: Hash.zero(),
            # g
            gas_ratio: 0,
            # o
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
    # Formula (C.23) v0.5.0
    def encode(%WorkResult{} = wr) do
      e_le(wr.service, 4) <>
        e({wr.code_hash, wr.payload_hash}) <>
        e_le(wr.gas_ratio, 8) <>
        do_encode(wr.result)
    end

    # Formula (C.28) v0.5.0
    defp do_encode({:ok, b}) do
      e({0, vs(b)})
    end

    # Formula (C.28) v0.5.0
    defp do_encode({:error, e}) do
      e(WorkExecutionError.code(e))
    end
  end

  use Sizes
  use Codec.Decoder

  def decode(bin) do
    <<service::binary-size(4), code_hash::binary-size(@hash_size),
      payload_hash::binary-size(@hash_size), gas_ratio::binary-size(8), error_code::8,
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
       service: de_le(service, 4),
       code_hash: code_hash,
       payload_hash: payload_hash,
       gas_ratio: de_le(gas_ratio, 8),
       result: result
     }, rest}
  end

  use JsonDecoder

  def json_mapping,
    do: %{service: :service_id, gas_ratio: :accumulate_gas, result: &parse_result/1}

  def parse_result(%{ok: ok}), do: {:ok, JsonDecoder.from_json(ok)}
  def parse_result(%{panic: _}), do: {:error, :panic}
end
