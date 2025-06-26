defmodule CommsTest do
  use ExUnit.Case, async: false
  alias Jamixir.Node
  alias Network.Types.SegmentShardsRequest
  alias Block.Extrinsic.Assurance
  alias Block.Extrinsic.WorkPackage
  alias Codec.State.Trie
  import Codec.Encoder
  import Mox
  import Jamixir.Factory
  import TestHelper
  require Logger
  alias Block.Extrinsic.{Disputes.Judgement, TicketProof}
  alias Network.{Config, Peer, PeerSupervisor}
  alias Quicer.Flags
  alias System.Audit.AuditAnnouncement
  import ExUnit.Assertions

  alias Util.Hash
  use Sizes

  @base_port 9999
  @dummy_protocol_id 242

  setup context do
    # Use a different port for each test based on its line number
    base_port = @base_port + (context.line || 0)

    {server_pid, client_pid, port} = start_peers_with_retry(base_port, 3)

    wait(fn -> Process.alive?(client_pid) end)
    wait(fn -> Process.alive?(server_pid) end)

    on_exit(fn ->
      if Process.alive?(server_pid), do: GenServer.stop(server_pid, :normal)
      if Process.alive?(client_pid), do: GenServer.stop(client_pid, :normal)
    end)

    {:ok, client: client_pid, port: port}
  end

  setup :set_mox_from_context

  # TODO fix network tests
  @moduletag :skip
  describe "basic messages" do
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
        for _ <- 1..40 do
          task = if :rand.uniform() > 0.5, do: valid_msg, else: invalid_msg

          Task.async(task)
        end

      Task.await_many(tasks, 10_000)
      assert Process.alive?(client), "Peer crashed during mixed message handling"
    end
  end

  # CE 128
  describe "request_blocks/4" do
    setup do
      blocks = for _ <- 1..300, {b, _} = Block.decode(File.read!("test/block_mock.bin")), do: b
      {:ok, blocks: blocks}
    end

    test "requests 9 blocks", %{client: client, blocks: blocks, port: _port} do
      Jamixir.NodeAPI.Mock
      |> expect(:get_blocks, fn <<0::hash()>>, :ascending, 9 -> {:ok, blocks} end)

      result = Peer.request_blocks(client, <<0::hash()>>, 0, 9)
      verify!()
      assert {:ok, ^blocks} = result
    end

    test "requests 2 blocks in descending order", %{client: client, blocks: blocks, port: _port} do
      Jamixir.NodeAPI.Mock
      |> expect(:get_blocks, fn <<1::hash()>>, :descending, 2 -> {:ok, blocks} end)

      result = Peer.request_blocks(client, <<1::hash()>>, 1, 2)
      verify!()
      assert {:ok, ^blocks} = result
    end
  end

  # CE 129
  describe "request_state/5" do
    setup do
      %{state: state} = build(:genesis_state_with_safrole)
      {:ok, state_trie: Trie.serialize(state)}
    end

    test "requests state smoke test", %{client: client, state_trie: state_trie} do
      block_hash = <<1::hash()>>
      start_key = Map.keys(state_trie) |> Enum.at(2)
      end_key = Map.keys(state_trie) |> Enum.at(5)
      bounderies = [<<1::4096>>, <<2::4096>>]

      Jamixir.NodeAPI.Mock
      |> expect(:get_state_trie, 1, fn ^block_hash -> {:ok, {state_trie, bounderies}} end)

      {:ok, {result_bounderies, result_trie}} =
        Peer.request_state(client, block_hash, start_key, end_key, 400_000)

      verify!()
      assert bounderies == result_bounderies

      assert map_size(result_trie) == 4

      for {key, value} <- state_trie, key >= start_key, key <= end_key do
        assert Map.get(result_trie, key) == value
      end
    end

    test "return only first state key/value when size is bigger than max_size", %{
      client: client,
      state_trie: state_trie
    } do
      [start_key, end_key] = Map.keys(state_trie) |> Enum.take(2)
      max_size = byte_size(state_trie[start_key])

      Jamixir.NodeAPI.Mock
      |> expect(:get_state_trie, 1, fn _ -> {:ok, {state_trie, []}} end)

      {:ok, {_, result_trie}} =
        Peer.request_state(client, <<1::hash()>>, start_key, end_key, max_size)

      verify!()

      assert map_size(result_trie) == 1

      assert result_trie[start_key] == state_trie[start_key]
    end

    test "single key state request", %{client: client, state_trie: state_trie} do
      [start_key | _] = Map.keys(state_trie)

      Jamixir.NodeAPI.Mock
      |> expect(:get_state_trie, 1, fn _ -> {:ok, {state_trie, []}} end)

      {:ok, {_, result_trie}} =
        Peer.request_state(client, <<1::hash()>>, start_key, start_key, 1000)

      verify!()

      assert map_size(result_trie) == 1
      assert result_trie[start_key] == state_trie[start_key]
    end
  end

  describe "distribute_ticket/3" do
    # CE 131
    test "distributes proxy ticket", %{client: client} do
      ticket = %TicketProof{attempt: 0, signature: <<9::m(bandersnatch_proof)>>}
      Jamixir.NodeAPI.Mock |> expect(:process_ticket, 1, fn :proxy, 77, ^ticket -> :ok end)
      {:ok, ""} = Peer.distribute_ticket(client, :proxy, 77, ticket)
      verify!()
    end

    # CE 132
    test "distributes validator ticket", %{client: client} do
      ticket = %TicketProof{attempt: 1, signature: <<10::m(bandersnatch_proof)>>}

      Jamixir.NodeAPI.Mock
      |> expect(:process_ticket, 1, fn :validator, 77, ^ticket -> :ok end)

      {:ok, ""} = Peer.distribute_ticket(client, :validator, 77, ticket)
      verify!()
    end
  end

  # CE 133
  describe "send_work_package/4" do
    test "sends work package", %{client: client} do
      {work_package, extrinsics} = work_package_and_its_extrinsic_factory()

      core = 3

      Jamixir.NodeAPI.Mock
      |> expect(:save_work_package, 1, fn ^work_package, ^core, ^extrinsics -> :ok end)

      {:ok, ""} = Peer.send_work_package(client, work_package, core, extrinsics)
      verify!()
    end
  end

  # CE 134
  describe "send_work_package_bundle/4" do
    test "sends work package bundle", %{client: client} do
      wp_bundle = WorkPackage.bundle_binary(build(:work_package))
      core = 3
      segment_root_mapping = %{Hash.zero() => Hash.one(), Hash.one() => Hash.two()}
      wr_hash = <<7::hash()>>
      signature = <<8::m(signature)>>

      Jamixir.NodeAPI.Mock
      |> expect(:save_work_package_bundle, 1, fn ^wp_bundle, ^core, ^segment_root_mapping ->
        {:ok, {wr_hash, signature}}
      end)

      {:ok, {^wr_hash, ^signature}} =
        Peer.send_work_package_bundle(client, wp_bundle, core, segment_root_mapping)

      verify!()
    end
  end

  # CE 135
  describe "distribute_guarantee/4" do
    test "distributes guarantee", %{client: client} do
      g = build(:guarantee)
      Jamixir.NodeAPI.Mock |> expect(:save_guarantee, 1, fn ^g -> :ok end)
      {:ok, ""} = Peer.distribute_guarantee(client, g)
      verify!()
    end
  end

  # CE 136
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

  # CE 137
  describe "request_segment/3" do
    test "request segment based on erasure_root and index", %{client: client} do
      erasure_root = <<1::hash()>>
      index = 8
      bundle_shard = <<1, 2, 3, 4>>
      segments = [<<1::m(segment_shard)>>, <<2::m(segment_shard)>>]
      justification = [<<0, 3::hash()>>, <<1, 4::hash(), 5::hash()>>]

      Jamixir.NodeAPI.Mock
      |> expect(:get_segment, 1, fn ^erasure_root, ^index ->
        {:ok, {bundle_shard, segments, justification}}
      end)

      {:ok, {b, s, j}} = Peer.request_segment(client, erasure_root, index)
      verify!()

      assert b == bundle_shard
      assert s == segments
      assert j == justification
    end
  end

  # CE 138
  describe "request_audit_shard/3" do
    test "request audit shard", %{client: client} do
      erasure_root = <<1::hash()>>
      index = 8
      bundle_shard = <<1, 2, 3, 4>>
      justification = [<<0, 3::hash()>>, <<1, 4::hash(), 5::hash()>>]

      Jamixir.NodeAPI.Mock
      |> expect(:get_segment, 1, fn ^erasure_root, ^index ->
        {:ok, {bundle_shard, [], justification}}
      end)

      {:ok, {b, j}} = Peer.request_audit_shard(client, erasure_root, index)
      verify!()

      assert b == bundle_shard
      assert j == justification
    end
  end

  describe "request_segment_shard/4" do
    setup do
      ids = [1, 4, 7, 9]

      requests = [
        %SegmentShardsRequest{
          erasure_root: <<1::hash()>>,
          segment_index: 8,
          shard_indexes: ids
        },
        %SegmentShardsRequest{
          erasure_root: <<2::hash()>>,
          segment_index: 9,
          shard_indexes: [1, 2]
        }
      ]

      {:ok, requests: requests}
    end

    # CE 139
    test "request segment shard", %{client: client, requests: [request1, request2]} do
      ids = request1.shard_indexes
      shards = for(i <- request1.shard_indexes, do: <<i::m(segment_shard)>>)

      call1 = fn <<1::hash()>>, 8, ^ids -> {:ok, shards} end
      call2 = fn <<2::hash()>>, 9, [1, 2] -> {:ok, shards |> Enum.take(2)} end
      expect(Jamixir.NodeAPI.Mock, :get_segment_shards, 1, call1)
      expect(Jamixir.NodeAPI.Mock, :get_segment_shards, 1, call2)

      {:ok, result} = Peer.request_segment_shards(client, [request1, request2], false)

      verify!()
      assert result == shards ++ Enum.take(shards, 2)
    end

    # CE 140
    test "request segment shard with justification", %{
      client: client,
      requests: [request1, request2]
    } do
      ids = request1.shard_indexes
      shards = for(i <- request1.shard_indexes, do: <<i::m(segment_shard)>>)

      call1 = fn <<1::hash()>>, 8, ^ids -> {:ok, shards} end
      call2 = fn <<2::hash()>>, 9, [1, 2] -> {:ok, shards |> Enum.take(2)} end
      expect(Jamixir.NodeAPI.Mock, :get_segment_shards, 1, call1)
      expect(Jamixir.NodeAPI.Mock, :get_segment_shards, 1, call2)

      call_justification = fn _, shard_idx, idx -> {:ok, <<shard_idx, idx>>} end
      expect(Jamixir.NodeAPI.Mock, :get_justification, 6, call_justification)

      {:ok, {shards_result, justifications}} =
        Peer.request_segment_shards(client, [request1, request2], true)

      verify!()
      assert shards_result == shards ++ Enum.take(shards, 2)
      assert justifications == [<<8, 1>>, <<8, 4>>, <<8, 7>>, <<8, 9>>, <<9, 1>>, <<9, 2>>]
    end
  end

  # CE 141
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

  # CE 142
  describe "announce_preimage/4" do
    test "announces preimage", %{client: client} do
      preimage_data = "test preimage"
      preimage_hash = Util.Hash.default(preimage_data)

      # The server automatically does bidirectional communication, so we need to expect both calls
      Jamixir.NodeAPI.Mock
      |> expect(:receive_preimage, 1, fn 44, ^preimage_hash, 1 ->
        Node.receive_preimage(44, preimage_hash, 1)
        :ok
      end)
      |> expect(:get_preimage, 1, fn ^preimage_hash -> {:ok, preimage_data} end)
      |> expect(:save_preimage, 1, fn ^preimage_data -> :ok end)

      {:ok, ""} = Peer.announce_preimage(client, 44, preimage_hash, 1)

      # Wait for the async bidirectional communication to complete
      wait(
        fn ->
          try do
            verify!() == :ok
          rescue
            Mox.VerificationError -> false
          end
        end,
        200
      )

      verify!()
    end
  end

  # CE 143
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

  # CE 144
  describe "announce_audit/3" do
    test "announces audit first tranche evidence", %{client: client} do
      audit_announcement = %AuditAnnouncement{
        tranche: 0,
        announcements: for(i <- 1..Constants.core_count(), do: {i, <<i::m(hash)>>}),
        header_hash: Hash.four(),
        signature: <<8::m(signature)>>,
        evidence: <<77::m(bandersnatch_signature)>>
      }

      Jamixir.NodeAPI.Mock |> expect(:save_audit, 1, fn ^audit_announcement -> :ok end)

      {:ok, ""} = Peer.announce_audit(client, audit_announcement)

      verify!()
    end

    test "announces audit tranche <> 0", %{client: client} do
      audit_announcement = %AuditAnnouncement{
        tranche: 1,
        announcements: for(i <- 1..Constants.core_count(), do: {i, <<i::m(hash)>>}),
        header_hash: Hash.four(),
        signature: <<8::m(signature)>>,
        # keep this as binary to simplify now
        # when audit is ready, review this
        evidence: <<10::800>>
      }

      Jamixir.NodeAPI.Mock |> expect(:save_audit, 1, fn ^audit_announcement -> :ok end)

      {:ok, ""} = Peer.announce_audit(client, audit_announcement)

      verify!()
    end
  end

  # CE 145
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

  describe "announce_block/3" do
    setup :set_mox_global

    test "handles multiple sequential block announcements", %{client: client} do
      header = build(:decodable_header)

      for slot <- 1..20 do
        Peer.announce_block(client, %{header | timeslot: slot}, slot)
      end

      assert Process.alive?(client), "Expected client to be alive after announcements"

      # time for async handling
      Process.sleep(50)

      # State assertions
      client_state = :sys.get_state(client)
      assert map_size(client_state.up_streams) == 1
      assert Map.has_key?(client_state.up_streams, 0)

      %{stream: stream} = client_state.up_streams[0]
      assert is_reference(stream)
    end

    # Ensure that announce_block/3 results in exactly `n` ServerCalls.call/2 invocations
    test "calls ServerCalls.call N times", %{client: client} do
      n = 10
      header = build(:decodable_header)

      ServerCallsMock
      |> expect(:call, n, fn 0, _ -> :ok end)

      for slot <- 1..n do
        Peer.announce_block(client, %{header | timeslot: slot}, slot)
      end

      # Wait for async delivery
      Process.sleep(100)
      verify!()
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

    test "can send a list of messages with just 1 FIN", %{client: client} do
      # Send a list of messages
      messages = [<<7::800>>, <<17::1600>>]
      {:ok, resp} = Peer.send(client, @dummy_protocol_id, messages)
      assert resp == <<7::800, 17::1600>>
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

  #    Helper function to reduce duplication
  defp assert_handles_malformed_message(client, payload, description) do
    client_state = :sys.get_state(client)
    {:ok, stream} = :quicer.start_stream(client_state.connection, Config.default_stream_opts())
    {:ok, _} = :quicer.send(stream, payload, Flags.send_flag(:fin))
    assert Process.alive?(client), "Peer crashed on #{description}"
  end

  #    Helper function to start multiple peers
  defp start_multiple_peers(mode, ports) do
    peers =
      for port <- ports do
        {:ok, pid} = PeerSupervisor.start_peer(mode, "::1", port)
        pid
      end

    {:ok, peers}
  end

  # Helper function to start peers with retry logic
  defp start_peers_with_retry(base_port, max_retries) do
    start_peers_with_retry(base_port, max_retries, 0)
  end

  defp start_peers_with_retry(_base_port, max_retries, attempt) when attempt >= max_retries do
    raise "Failed to start peers after #{max_retries} attempts"
  end

  defp start_peers_with_retry(base_port, max_retries, attempt) do
    port = base_port + attempt

    case start_peer_pair(port) do
      {:ok, server_pid, client_pid} ->
        {server_pid, client_pid, port}

      {:error, reason} ->
        Logger.debug("Attempt #{attempt + 1} failed on port #{port}: #{inspect(reason)}")
        # Wait a bit before retrying to avoid rapid port conflicts
        Process.sleep(10 + attempt * 5)
        start_peers_with_retry(base_port, max_retries, attempt + 1)
    end
  end

  defp start_peer_pair(port) do
    case PeerSupervisor.start_peer(:listener, "::1", port) do
      {:ok, server_pid} ->
        # Wait a bit for the server to be fully ready
        Process.sleep(10)

        case PeerSupervisor.start_peer(:initiator, "::1", port) do
          {:ok, client_pid} ->
            {:ok, server_pid, client_pid}

          {:error, reason} ->
            # Clean up server if client fails
            if Process.alive?(server_pid), do: GenServer.stop(server_pid, :normal)
            {:error, {:client_start_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:server_start_failed, reason}}
    end
  end
end
