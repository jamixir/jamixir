# Formula (B.6) v0.6.1
defmodule PVM.Host.Accumulate.Context do
  alias System.State.{Accumulation, ServiceAccount}

  @type t :: %__MODULE__{
          # s: Service index
          service: non_neg_integer(),
          # u: Accumulation state
          accumulation: Accumulation.t(),
          # i: Computed service index from check function
          computed_service: non_neg_integer(),
          # t: List of deferred transfers
          transfers: list(System.DeferredTransfer.t()),
          # y: accumulation trie result
          accumulation_trie_result: Types.Hash.t() | nil
        }

  defstruct services: %{},
            service: nil,
            accumulation: %Accumulation{},
            computed_service: nil,
            transfers: [],
            accumulation_trie_result: nil

  # Formula (B.7) v0.6.0
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

  @behaviour Access

  @impl Access
  def fetch(container, key) do
    Map.fetch(Map.from_struct(container), key)
  end

  @impl Access
  def get_and_update(container, key, fun) do
    value = Map.get(container, key)
    {get, update} = fun.(value)
    {get, Map.put(container, key, update)}
  end

  @impl Access
  def pop(container, key) do
    value = Map.get(container, key)
    {value, Map.put(container, key, nil)}
  end
end
