defmodule CommsTest do
  use ExUnit.Case, async: false
  import Mox
  import Jamixir.Factory
  require Logger
  alias Network.{Peer, Config}
  alias Quicer.Flags

  @base_port 9999

  setup_all do
    Logger.configure(level: :none)
    :ok
  end

  setup context do
    # Use a different port for each test based on its line number
    port = @base_port + (context.line || 0)
    blocks = for _ <- 1..3, {b, _} = Block.decode(File.read!("test/block_mock.bin")), do: b
    {server_pid, client_pid} = QuicTestHelper.start_quic_processes(port, :server, :client)

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
          {:ok, response} = Peer.send(client, 134, message)
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

      result = Peer.request_blocks(client, <<0::32>>, 0, 9)
      verify!()
      assert {:ok, ^blocks} = result
    end

    test "requests 2 blocks in descending order", %{client: client, blocks: blocks, port: _port} do
      Jamixir.NodeAPI.Mock
      |> expect(:get_blocks, fn 1, 1, 2 -> {:ok, blocks} end)

      result = Peer.request_blocks(client, <<1::32>>, 1, 2)
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
      Peer.announce_block(client, header, slot)
      # Give some time for stream setup
      Process.sleep(100)

      # # Second announcement should reuse the same stream
      Peer.announce_block(client, header, slot + 1)
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
        Peer.announce_block(client, %{header | timeslot: slot}, slot)
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

  describe "stream cleanup" do
    test "cleans up outgoing streams after completion", %{client: client} do
      # Send multiple messages
      for i <- 1..10 do
        {:ok, _} = Peer.send(client, 134, "message#{i}")
      end

      # Give some time for streams to close
      Process.sleep(100)

      # Get client's state
      client_state = :sys.get_state(client)

      # Verify outgoing streams were cleaned up
      assert map_size(client_state.outgoing_streams) == 0,
             "Expected outgoing streams to be cleaned up, but found: #{inspect(client_state.outgoing_streams)}"
    end

    test "handles rapid message sending without leaking streams", %{client: client} do
      # Send messages rapidly
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            {:ok, _} = Peer.send(client, 134, "message#{i}")
          end)
        end

      # Wait for all tasks to complete
      Task.await_many(tasks)
      # Give time for cleanup
      Process.sleep(100)

      # Verify state
      client_state = :sys.get_state(client)

      assert map_size(client_state.outgoing_streams) == 0,
             "Stream leak detected: #{map_size(client_state.outgoing_streams)} streams remaining"
    end
  end

  describe "error handling" do
    test "handles malformed messages without crashing", %{client: client} do
      cases = [
        {<<1>>, "single byte"},
        {<<1, 2, 3, 4>>, "less than header size (5 bytes)"},
        {<<134, 0, 0, 0, 10, 0>>, "length larger than actual payload (CE)"},
        {<<0, 0, 0, 0, 10, 0>>, "length larger than actual payload (UP)"},
        {<<134, 0, 0, 1, 0, 1, 2, 3, 4, 5>>, "length smaller than actual payload (CE)"},
        {<<0, 0, 0, 1, 0, 1, 2, 3, 4, 5>>, "length smaller than actual payload (UP)"},
        {<<>>, "empty message"}
      ]

      client_state = :sys.get_state(client)

      for {payload, description} <- cases do
        {:ok, stream} =
          :quicer.start_stream(client_state.connection, Config.default_stream_opts())

        {:ok, _} = :quicer.send(stream, payload, Flags.send_flag(:fin))
        Process.sleep(50)
        assert Process.alive?(client), "Peer crashed on #{description}"
      end
    end

    test "handles concurrent malformed and valid messages", %{client: client} do
      client_state = :sys.get_state(client)
      valid_msg = fn -> Peer.send(client, 134, "valid message") end

      invalid_msg = fn ->
        {:ok, stream} =
          :quicer.start_stream(client_state.connection, Config.default_stream_opts())

        {:ok, _} = :quicer.send(stream, <<1>>, Flags.send_flag(:fin))
      end

      tasks =
        for _ <- 1..50 do
          if :rand.uniform() > 0.5, do: Task.async(valid_msg), else: Task.async(invalid_msg)
        end

      Task.await_many(tasks, 5000)
      assert Process.alive?(client), "Peer crashed during mixed message handling"
    end

    # TODO: test not passing, need to implemnt logic on the reciever side (server)
    # to timeout when message is not complete and return a response to the client
    @tag :skip
    test "handles stream interruption", %{client: client} do
      client_state = :sys.get_state(client)
      {:ok, stream} = :quicer.start_stream(client_state.connection, Config.default_stream_opts())

      # Send partial message without FIN
      {:ok, _} = :quicer.send(stream, <<134, 0, 0, 5, 0>>, Flags.send_flag(:none))
      Process.sleep(50)

      # Abruptly close stream
      :quicer.shutdown_stream(stream)
      Process.sleep(50)

      assert Process.alive?(client), "Peer crashed on stream interruption"
    end

    test "handles rapid stream open/close without data", %{client: client} do
      client_state = :sys.get_state(client)

      for _ <- 1..20 do
        {:ok, stream} =
          :quicer.start_stream(client_state.connection, Config.default_stream_opts())

        :quicer.shutdown_stream(stream, 0)
      end

      Process.sleep(100)
      client_state = :sys.get_state(client)
      assert map_size(client_state.outgoing_streams) == 0, "Stream leak detected"
    end
  end
end
