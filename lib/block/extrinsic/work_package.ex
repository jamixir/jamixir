defmodule Block.Extrinsic.WorkPackage do
  @moduledoc """
  Defines a WorkPackage struct and its types.
  """
  alias Block.Extrinsic.WorkItem
  alias System.State.ServiceAccount
  alias Util.Hash
  use Codec.Encoder
  use Codec.Decoder
  use AccessStruct

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

  # Formula (14.2) v0.6.2
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

  # 12 * 2 ** 20
  @maximum_size Constants.max_work_package_size()

  def valid?(wp) do
    valid_data_segments?(wp) && valid_size?(wp) && valid_items?(wp)
  end

  def bundle_binary(%__MODULE__{} = wp) do
    e(
      {wp, for(w <- wp.work_items, do: WorkItem.extrinsic_data(w)),
       for(w <- wp.work_items, do: WorkItem.import_segment_data(w)),
       for(w <- wp.work_items, do: WorkItem.segment_justification(w))}
    )
  end

  # Formula (14.9) v0.6.3
  # pc
  def authorization_code(%__MODULE__{} = wp, services) do
    case ServiceAccount.historical_lookup(
           services[wp.service],
           wp.context.timeslot,
           wp.authorization_code_hash
         ) do
      nil ->
        nil

      bin ->
        {_, code} = VariableSize.decode(bin, :binary)
        code
    end
  end

  # Formula (14.9) v0.6.2
  # pa
  def implied_authorizer(%__MODULE__{} = wp, services) do
    Hash.default(authorization_code(wp, services) <> wp.parameterization_blob)
  end

  # Formula (14.5) v0.6.2
  defp valid_size?(%__MODULE__{work_items: work_items} = p) do
    byte_size(p.authorization_token) +
      byte_size(p.parameterization_blob) +
      Enum.reduce(work_items, 0, fn w, acc ->
        segments_size = length(w.import_segments) * Constants.segment_size()
        extrinsics_size = Enum.sum(for {_, e} <- w.extrinsic, do: e)
        acc + byte_size(w.payload) + segments_size + extrinsics_size
      end) <= @maximum_size
  end

  use Sizes

  # Formula 14.2 w  ∈ ⟦I⟧ 1∶I - I = 4
  defp valid_items?(%__MODULE__{work_items: []}), do: false
  defp valid_items?(%__MODULE__{work_items: pw}) when length(pw) > @max_work_items, do: false
  defp valid_items?(_), do: true

  # Formula (14.4) v0.6.3
  def valid_data_segments?(%__MODULE__{work_items: work_items}) do
    {exported_sum, imported_sum, extrinsic_sum} =
      Enum.reduce(work_items, {0, 0, 0}, fn item, {exported_acc, imported_acc, extrinsic_acc} ->
        {exported_acc + item.export_count, imported_acc + length(item.import_segments),
         extrinsic_acc + length(item.extrinsic)}
      end)

    # ∑we ≤ WM ^  ∑|wi| ≤ WM ^ ∑ ∣wx∣ ≤ T
    exported_sum <= Constants.max_imports_and_exports() and
      imported_sum <= Constants.max_imports_and_exports() and
      extrinsic_sum <= Constants.max_extrinsics()
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
    # Formula (C.25) v0.6.2
    def encode(%WorkPackage{} = wp) do
      e({
        vs(wp.authorization_token),
        t(wp.service),
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
    <<service::service(), bin::binary>> = bin
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
