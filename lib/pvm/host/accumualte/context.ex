defmodule PVM.Host.Accumulate.Context do
  alias System.State.{Accumulation, ServiceAccount}
  use AccessStruct

  # Formula (B.7) v0.7.2 - L
  @type t :: %__MODULE__{
          # s: Service index
          service: non_neg_integer(),
          # e: Accumulation state
          accumulation: Accumulation.t(),
          # i: Computed service index from check function
          computed_service: non_neg_integer(),
          # t: List of deferred transfers
          transfers: list(System.DeferredTransfer.t()),
          # y: accumulation trie result
          accumulation_trie_result: Types.hash() | nil,
          # p: preimages
          preimages: MapSet.t(Preimage.t())
        }

  defstruct services: %{},
            service: nil,
            accumulation: %Accumulation{},
            computed_service: nil,
            transfers: [],
            accumulation_trie_result: nil,
            preimages: MapSet.new()

  # Formula (B.8) v0.7.2
  # ∀x ∈ L ∶ x_s ≡ (x_e)_d[x_s]
  @spec accumulating_service(PVM.Host.Accumulate.Context.t()) :: ServiceAccount.t()
  def accumulating_service(%__MODULE__{} = x), do: x.accumulation.services[x.service]

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
