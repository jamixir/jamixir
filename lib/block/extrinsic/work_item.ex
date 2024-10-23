defmodule Block.Extrinsic.WorkItem do
  @moduledoc """
  Work Item
  Section 14.3
  """
  alias Util.Hash

  @type t :: %__MODULE__{
          # s
          service: non_neg_integer(),
          # c
          code_hash: Types.hash(),
          # y
          payload: binary(),
          # g
          gas_limit: non_neg_integer(),
          # e
          export_count: non_neg_integer(),
          # i
          # TODO: update the type to be H ∪ (H⊞)
          import_segments: list({Types.hash(), non_neg_integer()}),
          # x
          extrinsic: list({Types.hash(), non_neg_integer()})
        }

  # Formula (189) v0.4.1
  defstruct [
    # s: The identifier of the service to which it relates
    service: 0,
    # c: The code hash of the service at the time of reporting
    code_hash: Hash.zero(),
    # y: A payload blob
    payload: <<>>,
    # g: A gas limit
    gas_limit: 0,
    # e: The number of data segments exported by this work item
    export_count: 0,
    # i: A sequence of imported data segments identified by the root of the segments tree
    import_segments: [],
    # x: A sequence of hashed blob hashes and lengths to be introduced in this block
    extrinsic: []
  ]

  defimpl Encodable do
    alias Block.Extrinsic.WorkItem
    alias Codec.{Encoder, VariableSize}
    # Formula (309) v0.4.1
    def encode(%WorkItem{} = wi) do
      Encoder.encode({
        Encoder.encode_le(wi.service, 4),
        wi.code_hash,
        VariableSize.new(wi.payload),
        Encoder.encode_le(wi.gas_limit, 8),
        VariableSize.new(encode_import_segments(wi)),
        VariableSize.new(encode_extrinsic(wi)),
        Encoder.encode_le(wi.export_count, 2)
      })
    end

    use Codec.Encoder

    # TODO: align encoding with 0.4.1
    defp encode_import_segments(work_item) do
      for {h, i} <- work_item.import_segments, do: {h, e_le(i, 2)}
    end

    defp encode_extrinsic(work_item) do
      for {h, i} <- work_item.extrinsic, do: {h, e_le(i, 4)}
    end
  end

  use JsonDecoder
end
