defmodule Block.Extrinsic.Guarantee.WorkResult do
  @moduledoc """
  data conduit by which services’ states
  may be altered through the computation done within a
  work-package

  section 11.1.4
  Formula (122) v0.4.1
  """
  alias Block.Extrinsic.Guarantee.WorkExecutionError
  alias Block.Extrinsic.WorkItem

  @type error :: :out_of_gas | :unexpected_termination | :bad_code | :code_too_large

  @type t :: %__MODULE__{
          # s: the index of the service whose state is to be altered and thus whose refine code was already executed
          service_index: non_neg_integer(),
          # c: hash of the code of the service at the time of being reported
          code_hash: Types.hash(),
          # l: the hash of the payload (l) within the work item which was executed in the
          # refine stage to give this result
          payload_hash: Types.hash(),
          # g: the gas prioritization ratio used when determining how much
          # gas should be allocated to execute this item’s accumulate
          gas_prioritization_ratio: non_neg_integer(),
          # o: the output or error of the execution of the code, which may be either an
          # octet sequence in case it was successful, or a member of the set J if not
          output_or_error: {:ok, binary()} | {:error, WorkExecutionError.t()}
        }

  # s
  defstruct service_index: 0,
            # c
            code_hash: <<0::256>>,
            # l
            payload_hash: <<0::256>>,
            # g
            gas_prioritization_ratio: 0,
            # o
            output_or_error: {:ok, <<>>}

  @spec new(WorkItem.t(), {:ok, binary()} | {:error, WorkExecutionError.t()}) :: t
  def new(%WorkItem{} = wi, output) do
    %__MODULE__{
      service_index: wi.service_id,
      code_hash: wi.code_hash,
      payload_hash: Util.Hash.default(wi.payload_blob),
      gas_prioritization_ratio: wi.gas_limit,
      output_or_error: output
    }
  end

  defimpl Encodable do
    alias Block.Extrinsic.Guarantee.{WorkExecutionError, WorkResult}
    alias Codec.{Encoder, VariableSize}

    # Formula (306) v0.4.1
    def encode(%WorkResult{} = wr) do
      Encoder.encode_le(wr.service_index, 4) <>
        Encoder.encode({wr.code_hash, wr.payload_hash}) <>
        Encoder.encode_le(wr.gas_prioritization_ratio, 8) <>
        do_encode(wr.output_or_error)
    end

    # Formula (311) v0.4.1
    defp do_encode({:ok, b}) do
      Encoder.encode({0, VariableSize.new(b)})
    end

    # Formula (311) v0.4.1
    defp do_encode({:error, e}) do
      Encoder.encode(WorkExecutionError.code(e))
    end
  end
end
