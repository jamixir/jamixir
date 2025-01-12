defmodule Network.PeerRegistry do
  def start_link(opts \\ []) do
    Registry.start_link(keys: :unique, name: __MODULE__, opts: opts)
  end

  # Register a peer process with a unique identifier
  def register_peer(pid, identifier) do
    Registry.register(__MODULE__, identifier, pid)
  end

  # Look up a peer process by its identifier
  def lookup_peer(identifier) do
    case Registry.lookup(__MODULE__, identifier) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
