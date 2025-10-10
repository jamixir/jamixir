defmodule Jamixir.RPC.Server do
  @moduledoc """
  JSON-RPC server for JAM node RPC specification.

  Supports both HTTP and WebSocket transports on port 19800.
  """

  use GenServer
  alias Util.Logger, as: Log

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 19800)

    # Start Bandit server with our router
    {:ok, _pid} =
      Bandit.start_link(
        plug: Jamixir.RPC.Router,
        port: port,
        thousand_island_options: [num_acceptors: 10]
      )

    Log.info("🚀 RPC server started on port #{port}")
    Log.info("📡 HTTP endpoint: http://localhost:#{port}/rpc")
    Log.info("🔌 WebSocket endpoint: ws://localhost:#{port}/ws")

    {:ok, %{port: port}}
  end
end
