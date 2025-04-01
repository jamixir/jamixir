defmodule CommsTest do
  use ExUnit.Case, async: false
  alias Block.Extrinsic.Assurance
  use Codec.Encoder
  import Mox
  import Jamixir.Factory
  require Logger
  alias Block.Extrinsic.{Disputes.Judgement, TicketProof}
  alias Network.{Config, Peer, PeerSupervisor}
  alias Quicer.Flags
  alias Util.Hash
  use Sizes

  @base_port 9999
  @dummy_protocol_id 242

  setup_all do
    blocks = for _ <- 1..300, {b, _} = Block.decode(File.read!("test/block_mock.bin")), do: b
    {:ok, blocks: blocks}
  end

  setup context do
    # Use a different port for each test based on its line number
    port = @base_port + (context.line || 0)

    {:ok, server_pid} =
      PeerSupervisor.start_peer(:listener, "::1", port)

    Process.sleep(30)

    {:ok, client_pid} =
      PeerSupervisor.start_peer(:initiator, "::1", port)

    on_exit(fn ->
      if Process.alive?(server_pid), do: GenServer.stop(server_pid, :normal)
      if Process.alive?(client_pid), do: GenServer.stop(client_pid, :normal)
    end)

    {:ok, client: client_pid, port: port}
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

  describe "announce_preimage/4" do
    test "announces preimage", %{client: client} do
      Jamixir.NodeAPI.Mock |> expect(:receive_preimage, 1, fn 44, <<45::hash()>>, 1 -> :ok end)
      {:ok, ""} = Peer.announce_preimage(client, 44, <<45::hash()>>, 1)
      verify!()
    end
  end

  describe "distribute_assurance/4" do
    test "distributes assurance", %{client: client} do
      assurance = %Assurance{
        bitfield: <<999::m(bitfield)>>,
        hash: Util.Hash.random(),
        signature: <<123::m(signature)>>
      }

      Jamixir.NodeAPI.Mock |> expect(:save_assurance, 1, fn ^assurance -> :ok end)

      {:ok, ""} = Peer.distribute_assurance(client, assurance)

      verify!()
    end
  end

  describe "get_preimage/2" do
    test "get existing preimage", %{client: client} do
      Jamixir.NodeAPI.Mock
      |> expect(:get_preimage, 1, fn <<45::hash()>> -> {:ok, <<1, 2, 3>>} end)

      Jamixir.NodeAPI.Mock |> expect(:save_preimage, 1, fn <<1, 2, 3>> -> :ok end)
      :ok = Peer.get_preimage(client, <<45::hash()>>)
      verify!()
    end

    test "get unexisting preimage", %{client: client} do
      Jamixir.NodeAPI.Mock
      |> expect(:get_preimage, 1, fn <<45::hash()>> -> {:error, :not_found} end)

      {:error, :not_found} = Peer.get_preimage(client, <<45::hash()>>)
      verify!()
    end
  end

  describe "distribute_ticket/3" do
    test "distributes proxy ticket", %{client: client} do
      ticket = %TicketProof{attempt: 0, signature: <<9::m(bandersnatch_proof)>>}
      Jamixir.NodeAPI.Mock |> expect(:process_ticket, 1, fn :proxy, 77, ^ticket -> :ok end)
      {:ok, ""} = Peer.distribute_ticket(client, :proxy, 77, ticket)
      verify!()
    end

    test "distributes validator ticket", %{client: client} do
      ticket = %TicketProof{attempt: 1, signature: <<10::m(bandersnatch_proof)>>}

      Jamixir.NodeAPI.Mock
      |> expect(:process_ticket, 1, fn :validator, 77, ^ticket -> :ok end)

      {:ok, ""} = Peer.distribute_ticket(client, :validator, 77, ticket)
      verify!()
    end
  end

  describe "distribute_guarantee/4" do
    test "distributes guarantee", %{client: client} do
      g = build(:guarantee)
      Jamixir.NodeAPI.Mock |> expect(:save_guarantee, 1, fn ^g -> :ok end)
      {:ok, ""} = Peer.distribute_guarantee(client, g)
      verify!()
    end
  end

  describe "get_work_report/2" do
    test "get work report", %{client: client} do
      wr = build(:work_report)
      hash = h(e(wr))

      Jamixir.NodeAPI.Mock |> expect(:get_work_report, 1, fn ^hash -> {:ok, wr} end)

      {:ok, result} = Peer.get_work_report(client, hash)
      assert result == wr
      verify!()
    end

    test "work report not found", %{client: client} do
      hash = Hash.one()
      Jamixir.NodeAPI.Mock |> expect(:get_work_report, 1, fn ^hash -> {:error, :not_found} end)
      {:error, :not_found} = Peer.get_work_report(client, hash)
      verify!()
    end
  end

  describe "announce_judgement/4" do
    test "announces jedgement", %{client: client} do
      hash = Hash.two()
      epoch = 8
      judgement = %Judgement{vote: 1, validator_index: 7, signature: <<123::@signature_size*8>>}
      Jamixir.NodeAPI.Mock |> expect(:save_judgement, 1, fn ^epoch, ^hash, ^judgement -> :ok end)
      {:ok, ""} = Peer.announce_judgement(client, epoch, hash, judgement)
      verify!()
    end
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

  describe "announce_block/3" do
    test "handles multiple sequential block announcements", %{client: client} do
      header = build(:decodable_header)

      for slot <- 1..20 do
        Peer.announce_block(client, %{header | timeslot: slot}, slot)
      end

      # Verify we have exactly one UP stream
      client_state = :sys.get_state(client)
      assert map_size(client_state.up_streams) == 1
      assert Map.has_key?(client_state.up_streams, 0)

      # Verify the stream is valid
      %{stream: stream} = client_state.up_streams[0]
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
      Process.sleep(20)

      # Get client's state
      client_state = :sys.get_state(client)

      # Verify outgoing streams were cleaned up
      assert map_size(client_state.pending_responses) == 0,
             "Expected outgoing streams to be cleaned up, but found: #{inspect(client_state.pending_responses)}"
    end

    # @tag :skip
    test "can send a list of messages with just 1 FIN", %{client: client} do
      # Send a list of messages
      messages = [<<7>>, <<17>>]
      {:ok, _} = Peer.send(client, @dummy_protocol_id, messages)

      # Give some time for streams to close
      Process.sleep(20)

      # Get client's state
      client_state = :sys.get_state(client)

      # Verify outgoing streams were cleaned up
      assert map_size(client_state.pending_responses) == 0,
             "Expected outgoing streams to be cleaned up, but found: #{inspect(client_state.pending_responses)}"
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

      # Verify state
      client_state = :sys.get_state(client)

      assert map_size(client_state.pending_responses) == 0,
             "Stream leak detected: #{map_size(client_state.pending_responses)} streams remaining"
    end
  end

  @tag :skip
  # this test passing about 90% of the time, when running as mix test,
  #  about 10% of the time it times out, some unknown race condition i guess
  test "handles concurrent malformed and valid messages", %{client: client} do
    client_state = :sys.get_state(client)
    valid_msg = fn -> Peer.send(client, @dummy_protocol_id, "valid message") end

    invalid_msg = fn ->
      {:ok, stream} =
        :quicer.start_stream(client_state.connection, Config.default_stream_opts())

      {:ok, _} = :quicer.send(stream, <<1>>, Flags.send_flag(:fin))
    end

    tasks =
      for _ <- 1..20 do
        task = if :rand.uniform() > 0.5, do: valid_msg, else: invalid_msg

        Task.async(task)
      end

    Task.await_many(tasks, 5000)
    assert Process.alive?(client), "Peer crashed during mixed message handling"
  end

  describe "error handling" do
    # TODO: test not passing, need to implemnt logic on the reciever side (server)
    # to timeout when message is not complete and return a response to the client
    @tag :skip
    test "handles stream interruption", %{client: client} do
      client_state = :sys.get_state(client)
      {:ok, stream} = :quicer.start_stream(client_state.connection, Config.default_stream_opts())

      # Send partial message without FIN
      {:ok, _} = :quicer.send(stream, <<@dummy_protocol_id, 0, 0, 5, 0>>, Flags.send_flag(:none))
      Process.sleep(20)

      # Abruptly close stream
      :quicer.shutdown_stream(stream)
      Process.sleep(20)

      assert Process.alive?(client), "Peer crashed on stream interruption"
    end

    test "handles rapid stream open/close without data", %{client: client} do
      client_state = :sys.get_state(client)

      for _ <- 1..20 do
        {:ok, stream} =
          :quicer.start_stream(client_state.connection, Config.default_stream_opts())

        :quicer.shutdown_stream(stream, 0)
      end

      Process.sleep(20)
      client_state = :sys.get_state(client)
      assert map_size(client_state.pending_responses) == 0, "Stream leak detected"
    end
  end

  test "multiple peers can communicate simultaneously" do
    # Start 3 listeners on different ports
    listener_ports = [9001, 9002, 9003]
    {:ok, listeners} = start_multiple_peers(:listener, listener_ports)
    # Give listeners time to start
    Process.sleep(20)

    # Start 3 initiators connecting to the listeners
    {:ok, initiators} = start_multiple_peers(:initiator, listener_ports)
    # Give connections time to establish

    # Send messages between peers in parallel
    tasks =
      for {initiator, i} <- Enum.with_index(initiators) do
        Task.async(fn ->
          message = "Message from initiator #{i}"
          {:ok, response} = Peer.send(initiator, @dummy_protocol_id, message)
          assert response == message

          # Get peer state and verify stream cleanup
          Process.sleep(20)
          state = :sys.get_state(initiator)
          assert map_size(state.pending_responses) == 0

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

  describe "malformed message handling" do
    test "handles single byte message", %{client: client} do
      assert_handles_malformed_message(client, <<1>>, "single byte")
    end

    test "handles incomplete header", %{client: client} do
      assert_handles_malformed_message(client, <<1, 2, 3, 4>>, "less than header size (5 bytes)")
    end

    test "handles UP message with oversized length", %{client: client} do
      assert_handles_malformed_message(
        client,
        <<0, 0, 0, 0, 10, 0>>,
        "length larger than actual payload (UP)"
      )
    end

    test "handles CE message with undersized length", %{client: client} do
      payload = <<@dummy_protocol_id, 0, 0, 1, 0, 1, 2, 3, 4, 5>>
      assert_handles_malformed_message(client, payload, "length smaller than actual payload (CE)")
    end

    test "handles empty message", %{client: client} do
      assert_handles_malformed_message(client, <<>>, "empty message")
    end
  end

  # Helper function to reduce duplication
  defp assert_handles_malformed_message(client, payload, description) do
    client_state = :sys.get_state(client)
    {:ok, stream} = :quicer.start_stream(client_state.connection, Config.default_stream_opts())
    {:ok, _} = :quicer.send(stream, payload, Flags.send_flag(:fin))
    assert Process.alive?(client), "Peer crashed on #{description}"
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
