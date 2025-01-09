defmodule BasicQuicClientTest do
  use ExUnit.Case, async: false
  import Mox
  alias Quic.{Client, Server}
  require Logger

  @port 9999

  setup do
    # Start server and client for each test
    {:ok, server} = Server.start_link(@port)
    {:ok, client} = Client.start_link(port: @port)
    Process.sleep(100)

    # Cleanup after each test
    on_exit(fn ->
      if Process.alive?(server), do: Process.exit(server, :normal)
      if Process.alive?(client), do: Process.exit(client, :normal)
    end)

    blocks = for _ <- 1..3, {b, _} = Block.decode(File.read!("test/block_mock.bin")), do: b
    {:ok, client: client, blocks: blocks}
  end

  setup :set_mox_from_context

  describe "request_blocks/4" do
    test "requests 9 blocks", %{client: client, blocks: blocks} do
      Jamixir.NodeAPI.Mock
      |> expect(:get_blocks, fn 0, 0, 9 -> {:ok, blocks} end)

      result = Client.request_blocks(client, <<0::32>>, 0, 9)
      verify!()
      assert {:ok, ^blocks} = result
    end

    test "requests 2 blocks in descending order", %{client: client, blocks: blocks} do
      Jamixir.NodeAPI.Mock
      |> expect(:get_blocks, fn 1, 1, 2 -> {:ok, blocks} end)

      result = Client.request_blocks(client, <<1::32>>, 1, 2)
      verify!()
      assert {:ok, ^blocks} = result
    end
  end
end
