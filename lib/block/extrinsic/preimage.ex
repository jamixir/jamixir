defmodule Block.Extrinsic.Preimage do
  alias Codec.VariableSize
  alias Util.{Collections, Hash}
  import SelectiveMock
  # Formula (158) v0.4.5
  @type t :: %__MODULE__{
          # i
          service: non_neg_integer(),
          # d
          blob: binary()
        }

  # i
  defstruct service: 0,
            # d
            blob: <<>>

  # Formula (159) v0.4.5
  # Formula (160) v0.4.5
  @spec validate(list(t()), %{non_neg_integer() => System.State.ServiceAccount.t()}) ::
          :ok | {:error, String.t()}
  mockable validate(preimages, services) do
    # Formula (155) v0.4.5
    with :ok <- Collections.validate_unique_and_ordered(preimages, & &1.service),
         # Formula (160) v0.4.5
         :ok <- check_all_preimages(preimages, services) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def mock(:validate, _), do: :ok

  # Formula (160) v0.4.5
  @spec check_all_preimages(list(t()), %{non_neg_integer() => System.State.ServiceAccount.t()}) ::
          :ok | {:error, String.t()}
  defp check_all_preimages(preimages, services) do
    Enum.reduce_while(preimages, :ok, fn preimage, _acc ->
      if not_provided?(preimage, services) do
        {:cont, :ok}
      else
        {:halt, {:error, "Preimage already provided for service index #{preimage.service}"}}
      end
    end)
  end

  # Formula (160) v0.4.5
  @spec not_provided?(t(), %{non_neg_integer() => System.State.ServiceAccount.t()}) :: boolean()
  defp not_provided?(preimage, services) do
    case services[preimage.service] do
      nil ->
        false

      service_account ->
        preimage_hash = Hash.default(preimage.blob)
        preimage_size = byte_size(preimage.blob)

        not Map.has_key?(service_account.preimage_storage_p, preimage_hash) and
          Map.get(service_account.preimage_storage_l, {preimage_hash, preimage_size}, []) == []
    end
  end

  defimpl Encodable do
    use Codec.Encoder

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
