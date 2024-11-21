defmodule Block.Extrinsic.WorkPackage do
  @moduledoc """
  Defines a WorkPackage struct and its types.
  """
  alias Block.Extrinsic.WorkItem
  alias System.State.ServiceAccount
  alias Util.Hash
  use Codec.Encoder
  use Codec.Decoder

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

  # Formula (194) v0.4.5
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

  # Formula (198) v0.4.5
  # 12 * 2 ** 20
  @maximum_size 12_582_912

  def valid?(wp) do
    valid_data_segments?(wp) && valid_size?(wp)
  end

  # Formula (200) v0.4.5
  # pc
  def authorization_code(%__MODULE__{} = wp, services) do
    ServiceAccount.historical_lookup(
      services[wp.service],
      wp.context.timeslot,
      wp.authorization_code_hash
    )
  end

  # Formula (200) v0.4.5
  # pa
  def implied_authorizer(%__MODULE__{} = wp, services) do
    Hash.default(authorization_code(wp, services) <> wp.parameterization_blob)
  end

  # Formula (203) v0.4.5
  def segment_root(r) do
    # TODO ⊞ part
    r
  end

  # Formula (197) v0.4.5
  defp valid_size?(%__MODULE__{work_items: work_items}) do
    Enum.reduce(work_items, 0, fn i, acc ->
      part1 = length(i.import_segments) * Constants.wswe()
      part2 = Enum.sum(for {_, e} <- i.extrinsic, do: e)
      acc + part1 + part2
    end) <= @maximum_size
  end

  # Formula (196) v0.4.5
  defp valid_data_segments?(%__MODULE__{work_items: work_items}) do
    {exported_sum, imported_sum} =
      Enum.reduce(work_items, {0, 0}, fn item, {exported_acc, imported_acc} ->
        {exported_acc + item.export_count, imported_acc + length(item.import_segments)}
      end)

    exported_sum <= @maximum_exported_items and imported_sum <= @maximum_exported_items
  end

  use JsonDecoder

  def json_mapping do
    %{
      authorization_token: :authorization,
      service: :auth_code_host,
      authorization_code_hash: [&extract_code_hash/1, :authorizer],
      parameterization_blob: [&extract_params/1, :authorizer],
      context: %{m: RefinementContext, f: :context},
      work_items: [[WorkItem], :items]
    }
  end

  defp extract_code_hash(%{code_hash: c}), do: JsonDecoder.from_json(c)
  defp extract_params(%{params: p}), do: JsonDecoder.from_json(p)

  defimpl Encodable do
    alias Block.Extrinsic.WorkPackage
    use Codec.Encoder
    # Formula (315) v0.4.5
    def encode(%WorkPackage{} = wp) do
      e({
        vs(wp.authorization_token),
        e_le(wp.service, 4),
        wp.authorization_code_hash,
        vs(wp.parameterization_blob),
        wp.context,
        vs(wp.work_items)
      })
    end
  end

  use Sizes

  def decode(bin) do
    {authorization_token, bin} = VariableSize.decode(bin, :binary)
    <<service::binary-size(4), bin::binary>> = bin
    <<authorization_code_hash::binary-size(@hash_size), bin::binary>> = bin
    {parameterization_blob, bin} = VariableSize.decode(bin, :binary)
    {context, bin} = RefinementContext.decode(bin)
    {work_items, rest} = VariableSize.decode(bin, WorkItem)

    {%__MODULE__{
       authorization_token: authorization_token,
       service: de_le(service, 4),
       authorization_code_hash: authorization_code_hash,
       parameterization_blob: parameterization_blob,
       context: context,
       work_items: work_items
     }, rest}
  end
end
