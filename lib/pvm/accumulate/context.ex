# Formula (B.6) v0.5.2
defmodule PVM.Accumulate.Context do
  alias System.State.{Accumulation, ServiceAccount}

  @type t :: %__MODULE__{
          # d: Service accounts state without service s
          services: %{non_neg_integer() => ServiceAccount.t()},
          # s: Service index
          service: non_neg_integer(),
          # u: Accumulation state
          accumulation: Accumulation.t(),
          # i: Computed service index from check function
          computed_service: non_neg_integer(),
          # t: List of deferred transfers
          transfers: list(System.DeferredTransfer.t())
        }

  defstruct [
    :services,
    :service,
    :accumulation,
    :computed_service,
    transfers: []
  ]

  #Formula (B.7) v0.5.2
  @spec accumulating_service(PVM.AccumulationContext.t(), non_neg_integer()) :: ServiceAccount.t()
  def accumulating_service(%__MODULE__{} = x, s),
    do: get_in(x, [:accumulation, :services, s])
end
