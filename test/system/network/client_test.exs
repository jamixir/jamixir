defmodule System.Network.ClientTest do
  use ExUnit.Case, async: false
  import Mox
  alias System.Network.{Client, Server}

  @port 9999

  # needs this because server uses mock in another process
  setup :set_mox_from_context

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

    blocks = for _ <- 1..3, {b, _} = Block.decode(File.read!("test/block_mock.bin")), do: b

    # Return server context to tests
    {:ok, server: server_pid, blocks: blocks}
  end

  describe "ask_block/3" do
    @describetag :sequential

    test "asks 9 blocks", %{blocks: blocks} do
      Jamixir.NodeAPI.Mock |> expect(:get_blocks, fn 0, 0, 9 -> {:ok, blocks} end)
      result = Client.ask_block(<<0::32>>, 0, 9)
      verify!()

      assert result == blocks
    end

    test "asks 2 in desc order blocks", %{blocks: blocks} do
      Jamixir.NodeAPI.Mock |> expect(:get_blocks, fn 1, 1, 2 -> {:ok, blocks} end)
      result = Client.ask_block(<<1::32>>, 1, 2)
      verify!()
      assert result == blocks
    end
  end
end
