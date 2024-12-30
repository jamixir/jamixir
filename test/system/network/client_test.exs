defmodule System.Network.ClientTest do
  use ExUnit.Case, async: true

  alias System.Network.Server
  alias System.Network.Client

  @port 9999

  setup_all do
    # Start server in supervised process
    {:ok, server_pid} =
      Task.start(fn ->
        Server.start_server(@port)
      end)

    # Ensure server is running
    # Give server time to initialize
    :timer.sleep(10)

    # Cleanup callback
    on_exit(fn ->
      if Process.alive?(server_pid) do
        Process.exit(server_pid, :normal)
      end
    end)

    # Return server context to tests
    {:ok, server: server_pid}
  end

  test "ask_block" do
    blocks = Client.ask_block("hash", 0, 10)
    assert length(blocks) == 10
  end
end
