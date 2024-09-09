defmodule Block.Extrinsic.WorkPackage do
  @moduledoc """
  Defines a WorkPackage struct and its types.
  """
  alias Block.Extrinsic.WorkItem

  @type t :: %__MODULE__{
          # j
          authorization_token: binary(),
          # h
          service_index: integer(),
          # c
          authorization_code_hash: binary(),
          # p
          parameterization_blob: binary(),
          # x
          context: RefinementContext.t(),
          # i
          work_items: list(WorkItem.t())
        }

  # Formula (176) v0.3.4
  defstruct [
    # j
    authorization_token: <<>>,
    # h
    service_index: 0,
    # c
    authorization_code_hash: <<>>,
    # p
    parameterization_blob: <<>>,
    # x
    context: %RefinementContext{},
    # i
    work_items: []
  ]

  # 2^11
  @maximum_exported_items 2048
  def maximum_exported_items, do: @maximum_exported_items

  # Formula (180) v0.3.4
  # 12 * 2 ** 20
  @maximum_size 12_582_912
  def maximum_size, do: @maximum_size

  def valid?(wp) do
    valid_data_segments?(wp) && valid_size?(wp)
  end

  # Formula (179) v0.3.4
  defp valid_size?(%__MODULE__{work_items: work_items}) do
    Enum.reduce(work_items, 0, fn i, acc ->
      part1 = length(i.imported_data_segments) * Constants.wswc()
      part2 = i.blob_hashes_and_lengths |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      acc + part1 + part2
    end) <= @maximum_size
  end

  # Formula (178) v0.3.4
defp valid_data_segments?(%__MODULE__{work_items: work_items}) do
  {exported_sum, imported_sum} =
    Enum.reduce(work_items, {0, 0}, fn item, {exported_acc, imported_acc} ->
      {exported_acc + item.exported_data_segments_count, imported_acc + length(item.imported_data_segments)}
    end)

  exported_sum <= @maximum_exported_items and imported_sum <= @maximum_exported_items
end

  defimpl Encodable do
    alias Block.Extrinsic.WorkPackage
    alias Codec.{VariableSize, Encoder}
    # Formula (287) v0.3.4
    def encode(%WorkPackage{} = wp) do
      Encoder.encode({
        VariableSize.new(wp.authorization_token),
        Encoder.encode_le(wp.service_index, 4),
        wp.authorization_code_hash,
        VariableSize.new(wp.parameterization_blob),
        wp.context,
        VariableSize.new(wp.work_items)
      })
    end
  end
end
