defmodule System.State.PrivilegedServices do
  @moduledoc """
  Formula (96) v0.4.1

  Up to three services may be recognized as privileged, each with a specific role:

  - `manager_service` (χm): The index of the manager service, which can alter the service privileges.
  - `alter_authorizer_service` (χa): The index of the service able to alter the authorizer queue (φ).
  - `alter_validator_service` (χv): The index of the service able to alter the validator queue (ι).
  """

  @type t :: %__MODULE__{
          manager_service: non_neg_integer(),
          alter_authorizer_service: non_neg_integer(),
          alter_validator_service: non_neg_integer()
        }

  defstruct manager_service: 0,
            alter_authorizer_service: 0,
            alter_validator_service: 0

  defimpl Encodable do
    alias System.State.PrivilegedServices

    def encode(%PrivilegedServices{} = v) do
      Codec.Encoder.encode(
        [
          v.manager_service,
          v.alter_authorizer_service,
          v.alter_validator_service
        ]
        |> Enum.map(&Codec.Encoder.encode_le(&1, 4))
      )
    end
  end
end
