defmodule Jamixir do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Storage, [persist: Mix.env() != :test]},
      Network.PeerRegistry,
      Network.PeerSupervisor,
      Jamixir.TimeTicker
    ]

    opts = [strategy: :one_for_one, name: Jamixir.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config do
    Application.get_env(:jamixir, Jamixir)
  end

  def config(k), do: config()[k]
end
