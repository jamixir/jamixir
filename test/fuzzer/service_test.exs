defmodule Jamixir.FuzzerTest do
  use ExUnit.Case
  alias Codec.State.Trie.SerializedState
  alias Util.Hash
  alias Jamixir.Fuzzer.{Client, Service}
  alias Jamixir.Meta
  alias Codec.State.Trie
  alias Storage
  alias System.State.ServiceAccount
  import Jamixir.Factory
  import Codec.Encoder
  import TestVectorUtil

  @socket_path "/tmp/jamixir_fuzzer_test.sock"

  setup do
    if File.exists?(@socket_path), do: File.rm!(@socket_path)

    fuzzer_pid = Task.start_link(fn -> Service.accept(@socket_path) end)

    # Give it a moment to start
    Process.sleep(100)

    {:ok, client} = Client.connect(@socket_path)

    on_exit(fn ->
      Client.disconnect(client)
      if File.exists?(@socket_path), do: File.rm!(@socket_path)
      Storage.remove_all()
    end)

    {:ok, client: client, fuzzer_pid: fuzzer_pid}
  end

  describe "peer_info handler" do
    test "handles basic peer info exchange", %{client: client} do
      assert :ok = Client.send_peer_info(client, Meta.name(), {0, 1, 0}, {1, 0, 0})
      assert {:ok, :peer_info, data} = Client.receive_message(client)

      assert %{name: name, version: version, protocol: protocol} = data
      assert name == Meta.name()
      assert version == Meta.app_version()
      assert protocol == Meta.jam_version()
    end
  end

  describe "get_state handler" do
    test "handles get_state request", %{client: client} do
      state = build(:genesis_state_with_safrole).state

      header_hash = Hash.one()
      Storage.put(header_hash, state)

      assert :ok = Client.send_get_state(client, header_hash)
      assert {:ok, :state, incoming_state} = Client.receive_message(client)

      fields = Map.from_struct(state) |> Map.drop([:services])

      for {key, value} <- fields do
        assert value == Map.get(incoming_state, key)
      end

      service_field_keys = ServiceAccount.__struct__() |> Map.keys() |> List.delete(:storage)

      for service_key <- Map.keys(state.services) do
        for service_field_key <- service_field_keys do
          assert Map.get(Map.get(incoming_state.services, service_key), service_field_key) ==
                   Map.get(Map.get(state.services, service_key), service_field_key)
        end
      end
    end

    test "handles get_state request for non-existent state", %{client: client} do
      # Request a state that doesn't exist
      non_existent_hash = Hash.random()

      assert :ok = Client.send_get_state(client, non_existent_hash)

      # The service should not send a response for non-existent states
      # note, this is a guess, the protocol doesn't mention what to do in this case
      # and since the fuzzer is an intrenal test tool, this should not happen and should not really be a concern
      # We expect a timeout or error
      result = Client.receive_message(client, 1000)

      # The service logs an error but doesn't send a response for non-existent states
      # So we expect a timeout or error
      assert result == {:error, :closed}
    end
  end

  describe "set_state handler" do
    test "handles set_state request", %{client: client} do
      state = build(:genesis_state_with_safrole).state
      serialized_state = Trie.serialize(state)
      expected_state_root = Trie.state_root(serialized_state)
      header_hash = Hash.two()

      assert :ok = Client.send_set_state(client, header_hash, state)
      assert {:ok, :state_root, incoming_state_root} = Client.receive_message(client)

      assert incoming_state_root == expected_state_root
      assert Storage.get_state_root(header_hash) == incoming_state_root
    end
  end

  describe "import_block handler" do
    setup %{client: client} do
      {:ok, block_json} =
        fetch_and_parse_json(
          "00000001.json",
          "traces/fallback",
          "davxy",
          "jam-test-vectors",
          "master"
        )

      parent_hash = JsonDecoder.from_json(block_json[:block][:header][:parent])
      Storage.put(parent_hash, build(:header, timeslot: 0))

      # put the pre_state in storage under the parent hash
      pre_state_trie = Trie.from_json(block_json[:pre_state][:keyvals])
      pre_state = Trie.trie_to_state(pre_state_trie)
      Storage.put(parent_hash, pre_state)

      {:ok, client: client, parent_hash: parent_hash, pre_state: pre_state}
    end

    test "handles single import_block request", %{client: client} do
      {:ok, block_json} =
        fetch_and_parse_json(
          "00000001.json",
          "traces/fallback",
          "davxy",
          "jam-test-vectors",
          "master"
        )

      block = Block.from_json(block_json[:block])
      expected_trie = Trie.from_json(block_json[:post_state][:keyvals])
      expected_state_root = Trie.state_root(%SerializedState{data: expected_trie})
      header_hash = h(e(block.header))

      assert :ok = Client.send_import_block(client, block)
      assert {:ok, :state_root, incoming_state_root} = Client.receive_message(client)

      assert incoming_state_root == expected_state_root
      assert Storage.get_state_root(header_hash) == expected_state_root

      assert Storage.get_block(header_hash) == block
    end

    @tag :slow
    test "handles sequential import of 10 blocks", %{client: client} do
      block_range = 1..10

      for block_number <- block_range do
        file = String.pad_leading("#{block_number}", 8, "0")

        {:ok, block_json} =
          fetch_and_parse_json(
            "#{file}.json",
            "traces/fallback",
            "davxy",
            "jam-test-vectors",
            "master"
          )

        block = Block.from_json(block_json[:block])
        expected_trie = Trie.from_json(block_json[:post_state][:keyvals])
        expected_state_root = Trie.state_root(%SerializedState{data: expected_trie})
        header_hash = h(e(block.header))

        assert :ok = Client.send_import_block(client, block)
        assert {:ok, :state_root, incoming_state_root} = Client.receive_message(client)

        assert incoming_state_root == expected_state_root
        assert Storage.get_block(header_hash) == block
        assert Storage.get_state_root(header_hash) == expected_state_root
      end

      {:ok, final_block_json} =
        fetch_and_parse_json(
          "00000010.json",
          "traces/fallback",
          "davxy",
          "jam-test-vectors",
          "master"
        )

      final_block = Block.from_json(final_block_json[:block])
      final_header_hash = h(e(final_block.header))
      expected_final_trie = Trie.from_json(final_block_json[:post_state][:keyvals])

      # retrive final state and comapre to expected post state from trace
      assert :ok = Client.send_get_state(client, final_header_hash)
      assert {:ok, :state, retrieved_state} = Client.receive_message(client)

      assert Trie.serialize(retrieved_state).data == expected_final_trie
    end
  end
end
