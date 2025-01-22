defmodule Block.Extrinsic.Preimage do
  alias Codec.VariableSize
  alias Util.Collections
  import SelectiveMock
  use Codec.Encoder

  # Formula (12.28) v0.5.2
  @type t :: %__MODULE__{
          # s
          service: non_neg_integer(),
          # p
          blob: binary()
        }

  # s
  defstruct service: 0,
            # p
            blob: <<>>

  # Formula (12.29) v0.5.2
  @spec validate(list(t()), %{non_neg_integer() => System.State.ServiceAccount.t()}) ::
          :ok | {:error, String.t()}
  mockable validate(preimages, services) do
    # Formula (12.29) v0.5.2
    with :ok <- Collections.validate_unique_and_ordered(preimages, & &1.service),
         # Formula (12.31) v0.5.2
         :ok <- check_all_preimages(preimages, services) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def mock(:validate, _), do: :ok

  # Formula (12.31) v0.5.2
  @spec check_all_preimages(list(t()), %{non_neg_integer() => System.State.ServiceAccount.t()}) ::
          :ok | {:error, String.t()}
  defp check_all_preimages(preimages, services) do
    Enum.reduce_while(preimages, :ok, fn preimage, _acc ->
      if not_provided?(preimage, services) do
        {:cont, :ok}
      else
        {:halt, {:error, :preimage_unneeded}}
      end
    end)
  end

  # Formula (12.30) v0.5.2
  @spec not_provided?(t(), %{non_neg_integer() => System.State.ServiceAccount.t()}) :: boolean()
  def not_provided?(preimage, services) do
    case services[preimage.service] do
      nil ->
        false

      service_account ->
        preimage_hash = h(preimage.blob)
        preimage_size = byte_size(preimage.blob)

        not Map.has_key?(service_account.preimage_storage_p, preimage_hash) and
          Map.get(service_account.preimage_storage_l, {preimage_hash, preimage_size}) == []
    end
  end

  defimpl Encodable do
    use Codec.Encoder

    # Formula (C.15) v0.5.0
    def encode(%Block.Extrinsic.Preimage{service: s, blob: p}) do
      e_le(s, 4) <> e(vs(p))
    end
  end

  use Codec.Decoder

  def decode(bin) do
    <<service::binary-size(4), bin::binary>> = bin

    {blob, rest} = VariableSize.decode(bin, :binary)
    {%__MODULE__{service: de_le(service, 4), blob: blob}, rest}
  end

  use JsonDecoder

  def json_mapping do
    %{service: :requester}
  end
end
