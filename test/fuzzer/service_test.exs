defmodule Jamixir.FuzzerTest do
  use ExUnit.Case
  alias Codec.State.Trie.SerializedState
  alias Util.Hash
  alias Jamixir.Fuzzer.{Client, Service}
  alias Jamixir.Meta
  alias Codec.State.Trie
  alias Storage
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

      assert Trie.serialize(incoming_state) == Trie.serialize(state)
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

      assert Storage.get_state(header_hash) |> Trie.serialize() == serialized_state
      assert incoming_state_root == expected_state_root
      assert Storage.get_state_root(header_hash) == incoming_state_root
    end
  end

  describe "import_block handler" do
    test "handles import_block request with fallback test vector", %{client: client} do
      # Fetch fallback block 1 from test vectors (mimicking trace tests)
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

      block = Block.from_json(block_json[:block])

      expected_trie = Trie.from_json(block_json[:post_state][:keyvals])
      expected_state_root = Trie.state_root(%SerializedState{data: expected_trie})

      assert :ok = Client.send_import_block(client, block)
      assert {:ok, :state_root, incoming_state_root} = Client.receive_message(client)

      header_hash = h(e(block.header))
      assert incoming_state_root == expected_state_root
      assert Storage.get_state_root(header_hash) == expected_state_root

      # Assert that the block header is in storage
      assert Storage.get_block(header_hash) == block
    end
  end
end
