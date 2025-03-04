defmodule Network.PeerRegistry do
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :supervisor
    }
  end

  def start_link(_opts \\ []) do
    Registry.start_link(
      keys: :unique,
      name: __MODULE__,
      partitions: System.schedulers_online()
    )
  end

  def register_peer(pid, identifier) do
    Registry.register(__MODULE__, identifier, pid)
  end

  def lookup_peer(identifier) do
    case Registry.lookup(__MODULE__, identifier) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
