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

  # Formula (14.2) v0.6.0
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

  # 12 * 2 ** 20
  @maximum_size Constants.max_work_package_size()

  def valid?(wp) do
    valid_data_segments?(wp) && valid_size?(wp)
  end

  # Formula (14.9) v0.6.0
  # pc
  def authorization_code(%__MODULE__{} = wp, services) do
    ServiceAccount.historical_lookup(
      services[wp.service],
      wp.context.timeslot,
      wp.authorization_code_hash
    )
  end

  # Formula (14.9) v0.6.0
  # pa
  def implied_authorizer(%__MODULE__{} = wp, services) do
    Hash.default(authorization_code(wp, services) <> wp.parameterization_blob)
  end

  # Formula (14.12) v0.6.0
  def segment_root(r) do
    # TODO ⊞ part
    r
  end

  # Formula (14.5) v0.6.0
  defp valid_size?(%__MODULE__{work_items: work_items} = p) do
    byte_size(p.authorization_token) +
      byte_size(p.parameterization_blob) +
      Enum.reduce(work_items, 0, fn w, acc ->
        segments_size = length(w.import_segments) * Constants.segment_size()
        extrinsics_size = Enum.sum(for {_, e} <- w.extrinsic, do: e)
        acc + byte_size(w.payload) + segments_size + extrinsics_size
      end) <= @maximum_size
  end

  # Formula (14.4) v0.6.0
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
    # Formula (C.25) v0.6.0
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
    <<service::32-little, bin::binary>> = bin
    <<authorization_code_hash::binary-size(@hash_size), bin::binary>> = bin
    {parameterization_blob, bin} = VariableSize.decode(bin, :binary)
    {context, bin} = RefinementContext.decode(bin)
    {work_items, rest} = VariableSize.decode(bin, WorkItem)

    {%__MODULE__{
       authorization_token: authorization_token,
       service: service,
       authorization_code_hash: authorization_code_hash,
       parameterization_blob: parameterization_blob,
       context: context,
       work_items: work_items
     }, rest}
  end
end
