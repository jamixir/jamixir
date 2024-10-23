defmodule Block.Extrinsic.WorkPackage do
  @moduledoc """
  Defines a WorkPackage struct and its types.
  """
  alias Block.Extrinsic.WorkItem
  alias System.{State, State.ServiceAccount}
  alias Util.Hash

  @type t :: %__MODULE__{
          # j
          authorization_token: binary(),
          # h
          service: integer(),
          # u
          authorization_code_hash: binary(),
          # p
          parameterization_blob: binary(),
          # x
          context: RefinementContext.t(),
          # w
          work_items: list(WorkItem.t())
        }

  # Formula (188) v0.4.1
  defstruct [
    # j
    authorization_token: <<>>,
    # h
    service: 0,
    # u
    authorization_code_hash: <<>>,
    # p
    parameterization_blob: <<>>,
    # x
    context: %RefinementContext{},
    # w
    work_items: []
  ]

  # 2^11
  @maximum_exported_items 2048
  def maximum_exported_items, do: @maximum_exported_items

  # Formula (192) v0.4.1
  # 12 * 2 ** 20
  @maximum_size 12_582_912

  def valid?(wp) do
    valid_data_segments?(wp) && valid_size?(wp)
  end

  # Formula (194) v0.4.1
  # pc
  def authorization_code(%__MODULE__{} = wp, %State{services: s}) do
    ServiceAccount.historical_lookup(
      s[wp.service],
      wp.context.timeslot,
      wp.authorization_code_hash
    )
  end

  # Formula (194) v0.4.1
  # pa
  def implied_authorizer(%__MODULE__{} = wp, %State{} = state) do
    Hash.default(authorization_code(wp, state) <> wp.parameterization_blob)
  end

  # Formula (191) v0.4.1
  defp valid_size?(%__MODULE__{work_items: work_items}) do
    Enum.reduce(work_items, 0, fn i, acc ->
      part1 = length(i.import_segments) * Constants.wswc()
      part2 = Enum.sum(for {_, e} <- i.extrinsic, do: e)
      acc + part1 + part2
    end) <= @maximum_size
  end

  # Formula (190) v0.4.1
  defp valid_data_segments?(%__MODULE__{work_items: work_items}) do
    {exported_sum, imported_sum} =
      Enum.reduce(work_items, {0, 0}, fn item, {exported_acc, imported_acc} ->
        {exported_acc + item.export_count, imported_acc + length(item.import_segments)}
      end)

    exported_sum <= @maximum_exported_items and imported_sum <= @maximum_exported_items
  end

  defimpl Encodable do
    alias Block.Extrinsic.WorkPackage
    alias Codec.{Encoder, VariableSize}
    # Formula (308) v0.4.1
    def encode(%WorkPackage{} = wp) do
      Encoder.encode({
        VariableSize.new(wp.authorization_token),
        Encoder.encode_le(wp.service, 4),
        wp.authorization_code_hash,
        VariableSize.new(wp.parameterization_blob),
        wp.context,
        VariableSize.new(wp.work_items)
      })
    end
  end
end
