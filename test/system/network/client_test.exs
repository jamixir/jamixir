defmodule System.Network.ClientTest do
  use ExUnit.Case, async: false

  alias System.Network.{Client, Server}

  @port 9999

  setup_all do
    # Start server in supervised process
    {:ok, server_pid} =
      Task.start(fn ->
        Server.start_server(@port)
      end)

    # Ensure server is running
    # Give server time to initialize
    :timer.sleep(100)

    # Cleanup callback
    on_exit(fn ->
      if Process.alive?(server_pid) do
        Process.exit(server_pid, :normal)
      end
    end)

    # Return server context to tests
    {:ok, server: server_pid}
  end

  describe "ask_block/3" do
    @describetag :sequential

    test "asks 10 blocks" do
      blocks = Client.ask_block(<<0::32>>, 0, 9)
      assert length(blocks) == 9
    end

    test "asks 2 blocks" do
      blocks = Client.ask_block(<<0::32>>, 0, 2)
      assert length(blocks) == 2
    end
  end
end
