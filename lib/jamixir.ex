defmodule Jamixir do
  alias Network.PeerRegistry
  alias Network.PeerSupervisor
  use Application

  @impl true
  def start(_type, _args) do
    children = [PeerSupervisor, Jamixir.TimeTicker, Jamixir.NodeCLIServer]
    PeerRegistry.start_link()

    opts = [strategy: :one_for_one, name: Jamixir.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config do
    Application.get_env(:jamixir, Jamixir)
  end

  def config(k), do: config()[k]
end
