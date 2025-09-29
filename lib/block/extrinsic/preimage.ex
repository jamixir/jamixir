defmodule Block.Extrinsic.Preimage do
  alias Codec.VariableSize
  alias Util.Collections
  alias Util.Logger
  import SelectiveMock
  import Codec.Encoder
  import Util.Hex

  # Formula (12.35) v0.7.2
  @type t :: %__MODULE__{
          # s
          service: non_neg_integer(),
          # d
          blob: binary()
        }

  # s
  defstruct service: 0,
            # d
            blob: <<>>

  # Formula (12.36) v0.7.2
  @spec validate(list(t()), %{non_neg_integer() => System.State.ServiceAccount.t()}) ::
          :ok | {:error, String.t()}
  mockable validate(preimages, services) do
    # Formula (12.36) v0.7.2
    with :ok <- Collections.validate_unique_and_ordered(preimages, &{&1.service, &1.blob}),
         # Formula (12.37) v0.7.2
         :ok <- check_all_preimages(preimages, services) do
      :ok
    else
      {:error, :not_in_order} -> {:error, :preimages_not_sorted_unique}
      {:error, :duplicates} -> {:error, :preimages_not_sorted_unique}
      {:error, e} -> {:error, e}
    end
  end

  def mock(:validate, _), do: :ok

  # Formula (12.37) v0.7.2
  @spec check_all_preimages(list(t()), %{non_neg_integer() => System.State.ServiceAccount.t()}) ::
          :ok | {:error, String.t()}
  defp check_all_preimages(preimages, services) do
    Enum.reduce_while(preimages, :ok, fn preimage, _acc ->
      if not_provided?(preimage, services) do
        {:cont, :ok}
      else
        Logger.info(
          "Invalid Service or preimage hash #{b16(h(preimage.blob))} already in service (#{preimage.service})"
        )

        {:halt, {:error, :preimage_unneeded}}
      end
    end)
  end

  # Formula (12.22) v0.7.2 - Y:
  @spec not_provided?(t(), %{non_neg_integer() => System.State.ServiceAccount.t()}) :: boolean()
  def not_provided?(preimage, services) do
    not_provided?(services, preimage.service, preimage.blob)
  end

  # Formula (12.22) v0.7.2 - Y:
  @spec not_provided?(
          %{non_neg_integer() => System.State.ServiceAccount.t()},
          non_neg_integer(),
          binary()
        ) :: boolean()
  def not_provided?(services, service_index, blob) do
    case Map.get(services, service_index) do
      nil -> false
      sa -> get_in(sa, [:storage, {h(blob), byte_size(blob)}]) == []
    end
  end

  defimpl Encodable do
    import Codec.Encoder

    # Formula (C.18) v0.7.2
    def encode(%Block.Extrinsic.Preimage{service: service_index, blob: p}) do
      t(service_index) <> e(vs(p))
    end
  end

  def decode(bin) do
    <<service_index::m(service_index), bin::binary>> = bin

    {blob, rest} = VariableSize.decode(bin, :binary)
    {%__MODULE__{service: service_index, blob: blob}, rest}
  end

  use JsonDecoder

  def json_mapping do
    %{service: :requester}
  end
end
