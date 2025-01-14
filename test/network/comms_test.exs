defmodule CommsTest do
  use ExUnit.Case, async: false
  import Mox
  import Jamixir.Factory
  require Logger
  alias Network.{Peer, Config, PeerSupervisor, PeerRegistry}
  alias Quicer.Flags

  @base_port 9999
  @dummy_protocol_id 242

  setup_all do
    Logger.configure(level: :none)
    :ok
  end

  setup context do
    # Start and supervise the supervisors for this test
    start_supervised!(PeerSupervisor)
    PeerRegistry.start_link()
    # Use a different port for each test based on its line number
    port = @base_port + (context.line || 0)
    blocks = for _ <- 1..3, {b, _} = Block.decode(File.read!("test/block_mock.bin")), do: b

    {:ok, server_pid} =
      PeerSupervisor.start_peer(:listener, "::1", port)

    Process.sleep(50)

    {:ok, client_pid} =
      PeerSupervisor.start_peer(:initiator, "::1", port)

    Process.sleep(50)

    on_exit(fn ->
      if Process.alive?(server_pid), do: Process.exit(server_pid, :kill)
      if Process.alive?(client_pid), do: Process.exit(client_pid, :kill)
    end)

    {:ok, client: client_pid, blocks: blocks, port: port}
  end

  setup :set_mox_from_context

  test "parallel streams", %{client: client} do
    number_of_messages = 5

    tasks =
      for i <- 1..number_of_messages do
        Task.async(fn ->
          message = "Hello, server#{i}!"
          {:ok, response} = Peer.send(client, @dummy_protocol_id, message)
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
    test "handles multiple sequential block announcements", %{client: client} do
      header = build(:decodable_header)

      for slot <- 1..20 do
        Peer.announce_block(client, %{header | timeslot: slot}, slot)
      end

      Process.sleep(10)

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
        {:ok, _} = Peer.send(client, @dummy_protocol_id, "message#{i}")
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
            {:ok, _} = Peer.send(client, @dummy_protocol_id, "message#{i}")
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
        {<<@dummy_protocol_id, 0, 0, 0, 10, 0>>, "length larger than actual payload (CE)"},
        {<<0, 0, 0, 0, 10, 0>>, "length larger than actual payload (UP)"},
        {<<@dummy_protocol_id, 0, 0, 1, 0, 1, 2, 3, 4, 5>>,
         "length smaller than actual payload (CE)"},
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
      valid_msg = fn -> Peer.send(client, @dummy_protocol_id, "valid message") end

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
      {:ok, _} = :quicer.send(stream, <<@dummy_protocol_id, 0, 0, 5, 0>>, Flags.send_flag(:none))
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

  test "multiple peers can communicate simultaneously" do
    # Start 3 listeners on different ports
    listener_ports = [9001, 9002, 9003]
    {:ok, listeners} = start_multiple_peers(:listener, listener_ports)
    # Give listeners time to start
    Process.sleep(100)

    # Start 3 initiators connecting to the listeners
    {:ok, initiators} = start_multiple_peers(:initiator, listener_ports)
    # Give connections time to establish
    Process.sleep(100)

    # Send messages between peers in parallel
    tasks =
      for {initiator, i} <- Enum.with_index(initiators) do
        Task.async(fn ->
          message = "Message from initiator #{i}"
          {:ok, response} = Peer.send(initiator, @dummy_protocol_id, message)
          assert response == message

          # Get peer state and verify stream cleanup
          Process.sleep(50)
          state = :sys.get_state(initiator)
          assert map_size(state.outgoing_streams) == 0

          {i, response}
        end)
      end

    # Wait for all communications to complete
    results = Task.await_many(tasks, 5000)
    assert length(results) == length(initiators)

    # Cleanup
    for pid <- listeners ++ initiators do
      Process.exit(pid, :normal)
    end
  end

  # Helper function to start multiple peers
  defp start_multiple_peers(mode, ports) do
    peers =
      for port <- ports do
        {:ok, pid} = PeerSupervisor.start_peer(mode, "::1", port)
        pid
      end

    {:ok, peers}
  end
end
