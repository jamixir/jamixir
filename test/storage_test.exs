defmodule StorageTest do
  use ExUnit.Case
  use Codec.Encoder
  alias Util.Merklization
  alias CubDB.State
  alias Block.Header
  alias System.State
  alias Util.Hash
  import Jamixir.Factory

  setup do
    on_exit(fn ->
      :mnesia.clear_table(:jam_objects)
    end)
  end

  describe "KVStorage" do
    test "put/get basic operations" do
      assert :ok = KVStorage.put("key1", "value1")
      assert KVStorage.get("key1") == "value1"
    end

    test "put with map" do
      entries = %{
        "key1" => "value1",
        "key2" => "value2",
        "key3" => "value3"
      }

      assert :ok = KVStorage.put(entries)

      assert KVStorage.get("key1") == "value1"
      assert KVStorage.get("key2") == "value2"
      assert KVStorage.get("key3") == "value3"
    end

    test "put binary blob" do
      blob = <<1, 2, 3, 4>>
      assert :ok = KVStorage.put(blob)

      blob_hash = Util.Hash.default(blob)
      assert KVStorage.get(blob_hash) == blob
    end

    test "get with module decoding" do
      header = build(:decodable_header)
      encoded = Encodable.encode(header)
      hash = Util.Hash.default(encoded)

      KVStorage.put(hash, encoded)
      assert KVStorage.get(hash, Header) == header
    end

    test "remove key" do
      KVStorage.put("key1", "value1")
      assert :ok = KVStorage.remove("key1")
      assert KVStorage.get("key1") == nil
    end
  end

  describe "Storage" do
    test "initialization" do
      assert {:ok, _pid} = Storage.start_link()
      assert KVStorage.get("t:0") == nil
      assert KVStorage.get(:latest_timeslot) == 0
    end

    test "store and retrieve single header" do
      parent = build(:decodable_header, timeslot: 99)
      Storage.put(parent)
      header = %Header{parent | timeslot: 100, parent_hash: h(e(parent))}
      assert :ok = Storage.put(header)

      r = Header.decode(e(header))

      encoded = Encodable.encode(header)
      hash = Hash.default(encoded)
      header = Header.decode(e(parent))

      assert Storage.get(hash, Header) == header
      assert {1, ^header} = Storage.get_latest_header()
    end

    test "store and retrieve multiple headers" do
      headers = [
        build(:decodable_header, timeslot: 1),
        build(:decodable_header, timeslot: 2),
        build(:decodable_header, timeslot: 3)
      ]

      assert :ok = Storage.put(headers)

      # Verify latest header
      assert {3, last_header} = Storage.get_latest_header()
      assert last_header == List.last(headers)

      # Verify all headers are stored
      Enum.each(headers, fn header ->
        encoded = Encodable.encode(header)
        hash = Hash.default(encoded)
        assert Storage.get_header(hash) == header
      end)
    end

    test "store and retrieve state" do
      state = build(:state)
      assert :ok = Storage.put(state)
      assert Storage.get_state() == state
      assert is_binary(Storage.get_state_root())
    end

    test "get non-existent header" do
      assert Storage.get_header(Hash.random()) == nil
    end

    test "get latest header when storage is empty" do
      # Clear any existing data
      :mnesia.clear_table(:jam_objects)
      assert Storage.get_latest_header() == nil
    end
  end
end
