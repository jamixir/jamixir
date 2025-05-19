defmodule System.State.PrivilegedServices do
  @moduledoc """
  Formula (9.9) v0.6.5
  """
  alias Codec.JsonEncoder
  use Codec.Encoder
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
      <<v.privileged_services_service::m(service), v.authorizer_queue_service::m(service),
        v.next_validators_service::m(service)>> <>
        e(v.services_gas)
    end
  end

  use Sizes

  def decode(bin) do
    <<privileged_services_service::m(service), authorizer_queue_service::m(service),
      next_validators_service::m(service), rest::binary>> = bin

    {services_gas, rest} = VariableSize.decode(rest, :map_int)

    {%__MODULE__{
       privileged_services_service: privileged_services_service,
       authorizer_queue_service: authorizer_queue_service,
       next_validators_service: next_validators_service,
       services_gas: services_gas
     }, rest}
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
