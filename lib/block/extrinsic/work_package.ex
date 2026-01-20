defmodule Block.Extrinsic.WorkPackage do
  @moduledoc """
  Defines a WorkPackage struct and its types.
  """
  alias Block.Extrinsic.WorkItem
  alias Block.Extrinsic.WorkPackageBundle
  alias System.State.ServiceAccount
  use AccessStruct
  import Codec.Encoder
  alias Codec.VariableSize
  import Util.Collections, only: [sum_by: 2]
  use Sizes

  @type t :: %__MODULE__{
          # j
          authorization_token: binary(),
          # h
          service: integer(),
          # u
          authorization_code_hash: binary(),
          # f
          parameterization_blob: binary(),
          # x
          context: RefinementContext.t(),
          # w
          work_items: list(WorkItem.t())
        }

  # Formula (14.2) v0.7.2
  defstruct [
    # j
    authorization_token: <<>>,
    # h
    service: 0,
    # u
    authorization_code_hash: <<>>,
    # f
    parameterization_blob: <<>>,
    # c
    context: %RefinementContext{},
    # w
    work_items: []
  ]

  def valid?(wp) do
    valid_data_segments?(wp) && valid_size?(wp) && valid_items?(wp) && valid_gas?(wp)
  end

  def bundle_binary(%__MODULE__{} = wp), do: e(bundle(wp))

  def bundle(%__MODULE__{} = wp) do
    %WorkPackageBundle{
      work_package: wp,
      import_segments: for(w <- wp.work_items, do: WorkItem.import_segment_data(w)),
      justifications: for(w <- wp.work_items, do: WorkItem.segment_justification(w)),
      extrinsics: for(w <- wp.work_items, do: WorkItem.extrinsic_data(w))
    }
  end

  # Formula (14.10) v0.7.2
  # p_u
  def authorization_code(%__MODULE__{} = wp, services) do
    ServiceAccount.code_lookup(
      services[wp.service],
      wp.context.timeslot,
      wp.authorization_code_hash
    )
  end

  # Formula (14.10) v0.7.2
  # pa
  def implied_authorizer(%__MODULE__{} = wp) do
    h(wp.authorization_code_hash <> wp.parameterization_blob)
  end

  # Formula (14.5) v0.7.2
  defp valid_size?(%__MODULE__{work_items: work_items} = p) do
    byte_size(p.authorization_token) +
      byte_size(p.parameterization_blob) +
      sum_by(work_items, fn w ->
        byte_size(w.payload) + length(w.import_segments) * Constants.segment_size() +
          Enum.sum(for {_, e} <- w.extrinsic, do: e)
      end) <= Constants.max_work_package_size()
  end

  use Sizes

  # Formula (14.2) v0.7.2 - w  ∈ ⟦I⟧ 1∶I
  defp valid_items?(%__MODULE__{work_items: []}), do: false
  defp valid_items?(%__MODULE__{work_items: pw}) when length(pw) > @max_work_items, do: false
  defp valid_items?(_), do: true

  # Formula (14.4) v0.7.2
  def valid_data_segments?(%__MODULE__{work_items: work_items}) do
    {exported_sum, imported_sum, extrinsic_sum} =
      Enum.reduce(work_items, {0, 0, 0}, fn item, {exported_acc, imported_acc, extrinsic_acc} ->
        {exported_acc + item.export_count, imported_acc + length(item.import_segments),
         extrinsic_acc + length(item.extrinsic)}
      end)

    # ∑we ≤ W_X ^  ∑|wi| ≤ W_M ^ ∑ ∣wx∣ ≤ T
    exported_sum <= Constants.max_exports() and
      imported_sum <= Constants.max_imports() and
      extrinsic_sum <= Constants.max_extrinsics()
  end

  # Formula (14.8) v0.7.2
  def valid_gas?(%__MODULE__{work_items: work_items}) do
    Enum.reduce(work_items, 0, fn w, acc -> acc + w.accumulate_gas_limit end) <
      Constants.gas_accumulation() and
      Enum.reduce(work_items, 0, fn w, acc -> acc + w.refine_gas_limit end) <
        Constants.gas_refine()
  end

  use JsonDecoder

  def json_mapping do
    %{
      authorization_token: :authorization,
      service: :auth_code_host,
      authorization_code_hash: :auth_code_hash,
      parameterization_blob: :authorizer_config,
      context: %{m: RefinementContext, f: :context},
      work_items: [[WorkItem], :items]
    }
  end

  defimpl Encodable do
    alias Block.Extrinsic.WorkPackage
    import Codec.Encoder
    # Formula (C.28) v0.7.2
    def encode(%WorkPackage{} = wp) do
      e({
        t(wp.service),
        wp.authorization_code_hash,
        wp.context,
        vs(wp.authorization_token),
        vs(wp.parameterization_blob),
        vs(wp.work_items)
      })
    end
  end

  def extrinsic_defs(%__MODULE__{work_items: work_items}) do
    for(wi <- work_items, do: for(e <- wi.extrinsic, do: e)) |> List.flatten()
  end

  @spec organize_extrinsics(Block.Extrinsic.WorkPackage.t(), list(binary())) ::
          {:ok, list(list(binary()))} | {:error, :mismatched_extrinsics}
  def organize_extrinsics(%__MODULE__{} = wp, extrinsics) do
    result =
      Enum.reduce_while(wp.work_items, {{:ok, []}, extrinsics}, fn wi, {{_, acc}, exs} ->
        {to_take, rest} = Enum.split(exs, length(wi.extrinsic))

        if length(to_take) != length(wi.extrinsic) do
          {:halt, {{:error, :mismatched_extrinsics}, rest}}
        else
          valid =
            Enum.zip(wi.extrinsic, to_take)
            |> Enum.all?(fn {{hash, size}, ext} -> byte_size(ext) == size and hash == h(ext) end)

          if valid do
            {:cont, {{:ok, acc ++ [to_take]}, rest}}
          else
            {:halt, {{:error, :mismatched_extrinsics}, rest}}
          end
        end
      end)

    case result do
      {{:ok, organized}, _} -> {:ok, organized}
      _ -> {:error, :mismatched_extrinsics}
    end
  end

  def decode(bin) do
    <<service::service(), bin::binary>> = bin
    <<authorization_code_hash::b(hash), bin::binary>> = bin
    {context, bin} = RefinementContext.decode(bin)
    {authorization_token, bin} = VariableSize.decode(bin, :binary)
    {parameterization_blob, bin} = VariableSize.decode(bin, :binary)
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
