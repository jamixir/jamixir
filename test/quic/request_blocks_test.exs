defmodule BasicQuicClientTest do
  use ExUnit.Case, async: false
  import Mox
  alias Quic.{Client}
  require Logger

  @port 8999
  @server_name :quic_server_blocks_test
  @client_name :quic_client_blocks_test

  setup do
    {_server_pid, client_pid} = QuicTestHelper.start_quic_processes(@port, @server_name, @client_name)
    blocks = for _ <- 1..3, {b, _} = Block.decode(File.read!("test/block_mock.bin")), do: b
    {:ok, client: client_pid, blocks: blocks}
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
