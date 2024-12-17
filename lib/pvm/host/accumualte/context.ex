# Formula (B.6) v0.5.2
defmodule PVM.Host.Accumulate.Context do
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

  # Formula (B.7) v0.5.2
  @spec accumulating_service(PVM.Host.Accumulate.Context.t()) :: ServiceAccount.t()
  def accumulating_service(%__MODULE__{} = x),
    do: get_in(x, [:accumulation, :services, x.service])

  @spec update_accumulating_service(
          PVM.Host.Accumulate.Context.t(),
          list(atom() | non_neg_integer()),
          any()
        ) ::
          PVM.Host.Accumulate.Context.t()
  def update_accumulating_service(x, path, value) do
    put_in(x, [:accumulation, :services, x.service] ++ path, value)
  end
end
