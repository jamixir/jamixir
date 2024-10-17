defmodule System.AccumulationState do
  alias System.State.{ServiceAccount, Validator, PrivilegedServices}
  # Formula (169) v0.4.1
  @type t :: %__MODULE__{
          # d: Service accounts state (δ)
          services: %{integer() => ServiceAccount.t()},
          # i: Upcoming validator keys (ι)
          next_validators: list(Validator.t()),
          # q: Queue of work-reports (φ)
          authorizer_queue: list(list(Types.hash())),
          # x: Privileges state (χ)
          privileged_services: PrivilegedServices.t()
        }

  defstruct services: %{},
            next_validators: [],
            authorizer_queue: [[]],
            privileged_services: %PrivilegedServices{}
end
