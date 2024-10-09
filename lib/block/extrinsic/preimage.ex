defmodule Block.Extrinsic.Preimage do
  alias Util.{Collections, Hash}
  import SelectiveMock
  # Formula (154) v0.4.1
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

  # Formula (155) v0.4.1
  # Formula (156) v0.4.1
  @spec validate(list(t()), %{non_neg_integer() => System.State.ServiceAccount.t()}) ::
          :ok | {:error, String.t()}
  mockable validate(preimages, services) do
    # Formula (155) v0.4.1
    with :ok <- Collections.validate_unique_and_ordered(preimages, & &1.service_index),
         # Formula (156) v0.4.1
         :ok <- check_all_preimages(preimages, services) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def mock(:validate, _), do: :ok

  # Formula (156) v0.4.1
  @spec check_all_preimages(list(t()), %{non_neg_integer() => System.State.ServiceAccount.t()}) ::
          :ok | {:error, String.t()}
  defp check_all_preimages(preimages, services) do
    Enum.reduce_while(preimages, :ok, fn preimage, _acc ->
      if not_provided?(preimage, services) do
        {:cont, :ok}
      else
        {:halt, {:error, "Preimage already provided for service index #{preimage.service_index}"}}
      end
    end)
  end

  # Formula (156) v0.4.1
  @spec not_provided?(t(), %{non_neg_integer() => System.State.ServiceAccount.t()}) :: boolean()
  defp not_provided?(preimage, services) do
    case Map.get(services, preimage.service_index) do
      nil ->
        false

      service_account ->
        preimage_hash = Hash.default(preimage.data)
        preimage_size = byte_size(preimage.data)

        not Map.has_key?(service_account.preimage_storage_p, preimage_hash) and
          Map.get(service_account.preimage_storage_l, {preimage_hash, preimage_size}, []) == []
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
