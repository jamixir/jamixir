defmodule Block.Extrinsic.WorkItem do
  @moduledoc """
  Work Item
  Section 14.3
  """

  @type t :: %__MODULE__{
          # s
          service_id: non_neg_integer(),
          # c
          code_hash: Types.hash(),
          # y
          payload_blob: binary(),
          # g
          gas_limit: non_neg_integer(),
          # i
          imported_data_segments: list({Types.hash(), non_neg_integer()}),
          # x
          blob_hashes_and_lengths: list({Types.hash(), non_neg_integer()}),
          # e
          exported_data_segments_count: non_neg_integer()
        }

  # Formula (177) v0.3.4
  defstruct [
    # s: The identifier of the service to which it relates
    service_id: 0,
    # c: The code hash of the service at the time of reporting
    code_hash: <<0::256>>,
    # y: A payload blob
    payload_blob: <<>>,
    # g: A gas limit
    gas_limit: 0,
    # i: A sequence of imported data segments identified by the root of the segments tree
    imported_data_segments: [],
    # x: A sequence of hashed blob hashes and lengths to be introduced in this block
    blob_hashes_and_lengths: [],
    # e: The number of data segments exported by this work item
    exported_data_segments_count: 0
  ]

  defimpl Encodable do
    alias Block.Extrinsic.WorkItem
    alias Codec.{Encoder, VariableSize}
    # Formula (288) v0.3.4
    def encode(%WorkItem{} = wi) do
      Encoder.encode({
        Encoder.encode_le(wi.service_id, 4),
        wi.code_hash,
        VariableSize.new(wi.payload_blob),
        Encoder.encode_le(wi.gas_limit, 8),
        VariableSize.new(encode_imported_data_segments(wi)),
        VariableSize.new(encode_blob_hashes_and_lengths(wi)),
        Encoder.encode_le(wi.exported_data_segments_count, 2)
      })
    end

    defp encode_imported_data_segments(work_item) do
      Enum.map(work_item.imported_data_segments, fn {h, i} ->
        {h, Encoder.encode_le(i, 2)}
      end)
    end

    defp encode_blob_hashes_and_lengths(work_item) do
      Enum.map(work_item.blob_hashes_and_lengths, fn {h, i} ->
        {h, Encoder.encode_le(i, 4)}
      end)
    end
  end
end
