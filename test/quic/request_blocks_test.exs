defmodule QuicTest do
  use ExUnit.Case, async: false
  import Mox
  require Logger
  alias Quic.{Client}

  @base_port 9999

  setup_all do
    Logger.configure(level: :none)
    :ok
  end

  setup context do
    # Use a different port for each test based on its line number
    port = @base_port + (context.line || 0)
    blocks = for _ <- 1..3, {b, _} = Block.decode(File.read!("test/block_mock.bin")), do: b
    {server_pid, client_pid} = QuicTestHelper.start_quic_processes(port)

    on_exit(fn ->
      QuicTestHelper.cleanup_processes(server_pid, client_pid)
    end)

    {:ok, client: client_pid, blocks: blocks, port: port}
  end

  setup :set_mox_from_context

  test "parallel streams", %{client: client, port: _port} do
    number_of_messages = 2

    tasks =
      for i <- 1..number_of_messages do
        Task.async(fn ->
          message = "Hello, server#{i}!"
          {:ok, response} = Client.send(client, 127, message)
          Logger.info("[QUIC_TEST] Response #{i}: #{inspect(response)}")
          assert response == message
          i
        end)
      end

    results = Task.await_many(tasks, 5000)
    assert length(results) == number_of_messages
  end

  describe "request_blocks/4" do
    test "requests 9 blocks", %{client: client, blocks: blocks, port: _port} do
      Jamixir.NodeAPI.Mock
      |> expect(:get_blocks, fn 0, 0, 9 -> {:ok, blocks} end)

      result = Client.request_blocks(client, <<0::32>>, 0, 9)
      verify!()
      assert {:ok, ^blocks} = result
    end

    test "requests 2 blocks in descending order", %{client: client, blocks: blocks, port: _port} do
      Jamixir.NodeAPI.Mock
      |> expect(:get_blocks, fn 1, 1, 2 -> {:ok, blocks} end)

      result = Client.request_blocks(client, <<1::32>>, 1, 2)
      verify!()
      assert {:ok, ^blocks} = result
    end
  end
end
