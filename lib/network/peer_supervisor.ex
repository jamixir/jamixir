defmodule Network.PeerSupervisor do
  use DynamicSupervisor

  def start_link(args \\ []) do
    DynamicSupervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_peer(mode, ip, port) do
    normalized_ip = if is_list(ip), do: ip, else: to_charlist(ip)

    spec = %{
      id: {:peer, mode, normalized_ip, port},
      start: {Network.Peer, :start_link, [%{init_mode: mode, ip: normalized_ip, port: port}]},
      restart: :transient,
      type: :worker
    }

    DynamicSupervisor.start_child(
      __MODULE__,
      spec
    )
  end
end
