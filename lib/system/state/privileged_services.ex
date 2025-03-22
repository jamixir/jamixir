defmodule System.State.PrivilegedServices do
  @moduledoc """
  Formula (9.9) v0.6.2
  """
  alias Codec.JsonEncoder

  use JsonDecoder

  @type t :: %__MODULE__{
          # m
          privileged_services_service: non_neg_integer(),
          # a
          authorizer_queue_service: non_neg_integer(),
          # v
          next_validators_service: non_neg_integer(),
          # g
          services_gas: %{non_neg_integer() => non_neg_integer()}
        }

  defstruct privileged_services_service: 0,
            authorizer_queue_service: 0,
            next_validators_service: 0,
            services_gas: %{}

  defimpl Encodable do
    use Codec.Encoder
    alias System.State.PrivilegedServices

    def encode(%PrivilegedServices{} = v) do
      e(
        for s <- [
              v.privileged_services_service,
              v.authorizer_queue_service,
              v.next_validators_service
            ] do
          e_le(s, 4)
        end
      ) <> e(v.services_gas)
    end
  end

  def json_mapping do
    %{
      privileged_services_service: :chi_m,
      authorizer_queue_service: :chi_a,
      next_validators_service: :chi_v,
      services_gas: [:chi_g, %{}]
    }
  end

  def to_json_mapping,
    do: %{
      privileged_services_service: :chi_m,
      authorizer_queue_service: :chi_a,
      next_validators_service: :chi_v,
      services_gas: {:chi_g, &JsonEncoder.to_list(&1, :service, :gas)}
    }
end
