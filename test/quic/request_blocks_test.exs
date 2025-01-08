defmodule BasicQuicClientTest do
  use ExUnit.Case, async: false
  import Mox
  alias Quic.{Client, Server}
  require Logger

  setup do
    # Logger.configure(
    #   level: :debug,
    #   sync: false
    # )

    # Add filter for QUIC client logs
    # :logger.add_primary_filter(
    #   :quic_client_filter,
    #   {&QuicLogFilter.filter/2, []}
    # )

    :ok
  end

  @port 9999

  # needs this because server uses mock in another process
  setup :set_mox_from_context

  setup_all do
    # Start server in supervised process
    {:ok, server_pid} =
      Task.start(fn ->
        Server.start_link(@port)
      end)

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

  describe "request_blocks/4" do
    @describetag :sequential

    test "requests 9 blocks", %{blocks: blocks} do
      {:ok, client} = Client.start_link(port: @port)

      Jamixir.NodeAPI.Mock
      |> expect(:get_blocks, fn 0, 0, 9 -> {:ok, blocks} end)

      result = Client.request_blocks(client, <<0::32>>, 0, 9)
      verify!()

      assert match?({:ok, _}, result)
      {:ok, response} = result

      assert response == blocks
    end

    test "requests 2 blocks in descending order", %{blocks: blocks} do
      {:ok, client} = Client.start_link(port: @port)

      Jamixir.NodeAPI.Mock
      |> expect(:get_blocks, fn 1, 1, 2 -> {:ok, blocks} end)

      result = Client.request_blocks(client, <<1::32>>, 1, 2)
      verify!()

      assert match?({:ok, _}, result)
      {:ok, response} = result

      assert response == blocks
    end
  end
end
