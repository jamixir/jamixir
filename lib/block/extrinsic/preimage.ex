defmodule Block.Extrinsic.Preimage do
  alias Util.{Collections, Hash}
  # Formula (155) v0.3.4
  @type t :: %__MODULE__{
          # i
          service_index: non_neg_integer(),
          # d
          data: binary()
        }

  # i
  defstruct service_index: 0,
            # d
            data: <<>>

  # Formula (156) v0.3.4
  # Formula (157) v0.3.4
  @spec validate(list(t()), %{non_neg_integer() => System.State.ServiceAccount.t()}) ::
          :ok | {:error, String.t()}
  def validate(preimages, services) do
    # Formula (156) v0.3.4
    with :ok <- Collections.validate_unique_and_ordered(preimages, & &1.service_index),
         # Formula (157) v0.3.4
         :ok <- validate_all_preimages(preimages, services) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Formula (157) v0.3.4
  @spec validate_all_preimages(list(t()), %{non_neg_integer() => System.State.ServiceAccount.t()}) ::
          :ok | {:error, String.t()}
  defp validate_all_preimages(preimages, services) do
    Enum.reduce_while(preimages, :ok, fn preimage, _acc ->
      case validate_preimage(preimage, services) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # Formula (157) v0.3.4
  @spec validate_preimage(t(), %{non_neg_integer() => System.State.ServiceAccount.t()}) ::
          :ok | {:error, String.t()}
  defp validate_preimage(preimage, services) do
    case Map.get(services, preimage.service_index) do
      nil ->
        {:error, "Service account not found for index #{preimage.service_index}"}

      service_account ->
        preimage_hash = Hash.default(preimage.data)
        preimage_size = byte_size(preimage.data)

        cond do
          Map.has_key?(service_account.preimage_storage_p, preimage_hash) ->
            {:error, "Preimage hash already exists in service account #{preimage.service_index}"}

          Map.get(service_account.preimage_storage_l, {preimage_hash, preimage_size}, []) != [] ->
            {:error,
             "Preimage storage_l is not empty for hash and size in service account #{preimage.service_index}"}

          true ->
            :ok
        end
    end
  end

  defimpl Encodable do
    def encode(%Block.Extrinsic.Preimage{service_index: i, data: d}) do
      Codec.Encoder.encode({
        i,
        d
      })
    end
  end
end
