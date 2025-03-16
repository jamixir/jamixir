defmodule Jamixir do
  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    keys_file = System.get_env("KEYS_FILE") || Application.get_env(:jamixir, :keys_file)
    genesis_file = System.get_env("GENESIS_FILE") || Application.get_env(:jamixir, :genesis_file)
    port = System.get_env("PORT") || Application.get_env(:jamixir, :port)

    Logger.info("Starting Jamixir node with keys #{keys_file} and genesis #{genesis_file}")

    :ok = load_keys(keys_file)
    :ok = load_genesis(genesis_file)
    :ok = load_port(port)
    Application.put_env(:jamixir, :port, port)

    children = [
      Network.PeerRegistry,
      Network.PeerSupervisor,
      Jamixir.TimeTicker,
      Jamixir.NodeCLIServer
    ]

    opts = [strategy: :one_for_one, name: Jamixir.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config do
    Application.get_env(:jamixir, Jamixir)
  end

  def config(k), do: config()[k]

  defp load_keys(file) do
    KeyManager.load_keys(file)
    Logger.info("Keys loaded successfully from #{file}")
    :ok
  end

  defp load_genesis(file) do
    Application.put_env(:jamixir, :genesis_file, file)
    Logger.info("Genesis file loaded from #{file}")
    :ok
  end

  defp load_port(port) do
    Application.put_env(:jamixir, :port, port)
    Logger.info("Port loaded from #{port}")
    :ok
  end
end
