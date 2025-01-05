defmodule Block.Extrinsic.WorkPackage do
  @moduledoc """
  Defines a WorkPackage struct and its types.
  """
  alias Block.Extrinsic.{WorkItem, Guarantees.WorkReport}
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

  # Formula (14.6) v0.5.3
  # 12 * 2 ** 20
  @maximum_size 12_582_912

  def valid?(wp) do
    valid_data_segments?(wp) && valid_size?(wp)
  end

  # Formula (14.9) v0.5.3
  # pc
  def authorization_code(%__MODULE__{} = wp, services) do
    code =
      ServiceAccount.historical_lookup(
        services[wp.service],
        wp.context.timeslot,
        wp.authorization_code_hash
      )

    if code == nil, do: {:error, :preimage_not_available}, else: code
  end

  # Formula (14.9) v0.5.3
  # pa
  def implied_authorizer(%__MODULE__{} = wp, services) do
    case authorization_code(wp, services) do
      {:error, :preimage_not_available} ->
        {:error, :preimage_not_available}

      code ->
        Hash.default(code <> wp.parameterization_blob)
    end
  end

  # Formula (203) v0.4.5
  @spec segment_root(Types.hash(), %{Types.hash() => Types.hash()}) :: Types.hash()
  def segment_root(r, _segment_root_dictionary) do
    # TODO ⊞ part
    r
  end

  # Formula (14.5) v0.5.3
  defp valid_size?(%__MODULE__{
         work_items: work_items,
         authorization_token: auth_token,
         parameterization_blob: param_blob
       }) do
    base_size = byte_size(auth_token) + byte_size(param_blob)

    items_size =
      for %WorkItem{payload: p, import_segments: i, extrinsic: x} <- work_items do
        byte_size(p) +
          length(i) * Constants.wswe() +
          Enum.sum(for {_, size} <- x, do: size)
      end

    base_size + Enum.sum(items_size) <= @maximum_size
  end

  # Formula (196) v0.4.5
  defp valid_data_segments?(%__MODULE__{work_items: work_items}) do
    {exported_sum, imported_sum} =
      Enum.reduce(work_items, {0, 0}, fn item, {exported_acc, imported_acc} ->
        {exported_acc + item.export_count, imported_acc + length(item.import_segments)}
      end)

    exported_sum <= @maximum_exported_items and imported_sum <= @maximum_exported_items
  end

  # Formula (14.7) v0.5.3
  defp valid_gas?(%__MODULE__{work_items: work_items}) do
    {acc_sum, refine_sum} =
      for %WorkItem{accumulate_gas_limit: wa, refine_gas_limit: wr} <- work_items,
          reduce: {0, 0} do
        {acc, ref} -> {acc + wa, ref + wr}
      end

    acc_sum < Constants.gas_accumulation() and refine_sum < Constants.gas_refine()
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
    # Formula (C.25) v0.5.0
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

  @doc """
  Formula (14.11) v0.5.3
  Computes work results for a given work package and core.
  Must be evaluated within 8 epochs of a recently finalized block.
  """
  @spec compute_work_result(t(), non_neg_integer()) ::
          {:error, :not_in_set} | WorkReport.t()
  def compute_work_result(%__MODULE__{} = work_package, core) do
    # TODO: Implement work result computation
    # - Check if o ∈ Y
    # - If not, return {:error, :not_in_set}
    # - If yes, return WorkResult with (s, x: px, c, a: pa, o, l, r)
  end
end
