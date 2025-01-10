defmodule CommsTest do
  use ExUnit.Case, async: false
  import Mox
  import Jamixir.Factory
  require Logger
  alias Network.Client

  @base_port 9999

  setup_all do
    Logger.configure(level: :info)
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
    number_of_messages = 100

    tasks =
      for i <- 1..number_of_messages do
        Task.async(fn ->
          message = "Hello, server#{i}!"
          {:ok, response} = Client.send(client, 134, message)
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

  describe "block announcements" do
    test "announces blocks over UP stream", %{client: client} do
      # Mock header and slot for announcement
      header = build(:decodable_header)
      slot = 42

      # First announcement should create UP stream
      Client.announce_block(client, header, slot)
      # Give some time for stream setup
      Process.sleep(100)

      # # Second announcement should reuse the same stream
      Client.announce_block(client, header, slot + 1)
      Process.sleep(100)

      # # Get client's state to verify UP stream handling
      client_state = :sys.get_state(client)

      # # Verify we have exactly one UP stream for protocol 0
      assert map_size(client_state.up_streams) == 1
      assert Map.has_key?(client_state.up_streams, 0)

      # # Verify the stream is valid
      %{stream_id: stream} = client_state.up_streams[0]
      assert is_reference(stream)
    end

    test "handles multiple sequential block announcements", %{client: client} do
      header = build(:decodable_header)


      for slot <- 1..100 do
        Client.announce_block(client, %{header | timeslot: slot}, slot)
        Process.sleep(20)
      end

      # Verify we have exactly one UP stream
      client_state = :sys.get_state(client)
      assert map_size(client_state.up_streams) == 1
      assert Map.has_key?(client_state.up_streams, 0)

      # Verify the stream is valid
      %{stream_id: stream} = client_state.up_streams[0]
      assert is_reference(stream)
    end
  end
end
