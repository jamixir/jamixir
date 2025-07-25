defmodule StorageTest do
  use ExUnit.Case, async: false
  alias Codec.State.Trie
  alias System.State
  alias Util.Hash
  use StoragePrefix
  import Jamixir.Factory
  import Codec.Encoder
  import TestHelper
  use StoragePrefix

  setup_all do
    Storage.remove_all()

    :ok
  end

  test "basic storage operations" do
    Storage.put("key1", "value1")
    assert Storage.get("key1") == "value1"
  end

  describe "KVStorage" do
    test "put/get basic operations" do
      assert {:ok, _} = KVStorage.put("key1", "value1")
      assert KVStorage.get("key1") == "value1"
    end

    test "put with map" do
      entries = %{
        "key1" => "value1",
        "key2" => "value2",
        "key3" => "value3"
      }

      assert {:ok, ["key1", "key2", "key3"]} = KVStorage.put(entries)

      assert KVStorage.get("key1") == "value1"
      assert KVStorage.get("key2") == "value2"
      assert KVStorage.get("key3") == "value3"
    end

    test "put binary blob" do
      blob = <<1, 2, 3, 4>>
      blob_hash = Util.Hash.default(blob)
      assert {:ok, ^blob_hash} = KVStorage.put(blob_hash, blob)

      assert KVStorage.get(blob_hash) == blob
    end

    test "get with module decoding" do
      header = build(:decodable_header)
      encoded = Encodable.encode(header)
      hash = Util.Hash.default(encoded)

      KVStorage.put(hash, header)
      assert KVStorage.get(hash) == header
    end

    test "remove key" do
      KVStorage.put("key1", "value1")
      assert :ok = KVStorage.remove("key1")
      assert KVStorage.get("key1") == nil
    end
  end

  describe "Storage" do
    test "store and retrieve single header" do
      header = build(:decodable_header)
      assert {:ok, hash} = Storage.put(header)
      assert Storage.get(hash) == header
      assert {5, ^header} = Storage.get_latest_header()
    end

    test "store and retrieve multiple headers" do
      headers = [
        build(:decodable_header, timeslot: 1),
        build(:decodable_header, timeslot: 2),
        build(:decodable_header, timeslot: 3)
      ]

      assert {:ok, _hashes} = Storage.put(headers)

      # Verify latest header
      assert {3, last_header} = Storage.get_latest_header()
      assert last_header == List.last(headers)

      # Verify all headers are stored
      Enum.each(headers, fn header ->
        encoded = Encodable.encode(header)
        hash = Hash.default(encoded)
        assert Storage.get(hash) == header
      end)
    end

    test "store and retrieve state" do
      state = %State{}
      state_root = Trie.state_root(state)
      header_hash = Hash.random()
      assert ^state_root = Storage.put(header_hash, state)
      assert Storage.get_state(header_hash) == state
      assert Storage.get_state_root(header_hash) == state_root
      Storage.remove("#{@p_state}#{header_hash}")
      Storage.remove("#{@p_state_root}#{header_hash}")
    end

    test "store and retrieve state fields" do
      state = %State{}
      header_hash = Hash.random()
      Storage.put(header_hash, state)

      for key <- Map.keys(Map.from_struct(state)) do
        assert Storage.get_state(header_hash, key) == Map.get(state, key)
      end
    end

    test "get non-existent header" do
      assert Storage.get(Hash.random()) == nil
    end

    test "get latest header when key is empty" do
      Storage.remove("latest_timeslot")
      assert Storage.get_latest_header() == nil
    end
  end

  describe "put and get block" do
    setup_validators(1)

    test "put and get block" do
      block = build(:decodable_block)
      {:ok, _key} = Storage.put(block)
      header_hash = h(e(block.header))
      assert Storage.get_block(header_hash) == block
      assert Storage.get_next_block(block.header.parent_hash) == header_hash
    end
  end

  describe "put_ticket/2" do
    test "get tickets for inexistent epoch" do
      assert Storage.get_tickets(999) == []
    end

    test "put and get ticket" do
      [t1, t2] = build_list(2, :ticket_proof, attempt: 0)
      assert {:ok, _} = Storage.put(1, t1)
      assert {:ok, _} = Storage.put(1, t2)
      assert Storage.get_tickets(1) == [t1, t2]
    end

    test "put and get ticket different epochs" do
      [t1, t2] = build_list(2, :ticket_proof, attempt: 0)
      assert {:ok, _} = Storage.put(7, t1)
      assert {:ok, _} = Storage.put(8, t2)
      assert Storage.get_tickets(7) == [t1]
      assert Storage.get_tickets(8) == [t2]
    end
  end
end
