defmodule System.State.PrivilegedServices do
  @moduledoc """
  Formula (9.9) v0.6.2
  """
  alias Codec.JsonEncoder

  use JsonDecoder

  @type t :: %__MODULE__{
          # m
          manager_service: non_neg_integer(),
          # a
          alter_authorizer_service: non_neg_integer(),
          # v
          alter_validator_service: non_neg_integer(),
          # g
          services_gas: %{non_neg_integer() => non_neg_integer()}
        }

  defstruct manager_service: 0,
            alter_authorizer_service: 0,
            alter_validator_service: 0,
            services_gas: %{}

  defimpl Encodable do
    use Codec.Encoder
    alias System.State.PrivilegedServices

    def encode(%PrivilegedServices{} = v) do
      e(
        for s <- [v.manager_service, v.alter_authorizer_service, v.alter_validator_service] do
          e_le(s, 4)
        end
      ) <> e(v.services_gas)
    end
  end

  def json_mapping do
    %{
      manager_service: :chi_m,
      alter_authorizer_service: :chi_a,
      alter_validator_service: :chi_v,
      services_gas: [:chi_g, %{}]
    }
  end

  def to_json_mapping,
    do: %{
      manager_service: :chi_m,
      alter_authorizer_service: :chi_a,
      alter_validator_service: :chi_v,
      services_gas: {:chi_g, &JsonEncoder.to_list(&1, :service, :gas)}
    }
end
