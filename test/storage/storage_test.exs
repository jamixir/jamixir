defmodule StorageTest do
  use ExUnit.Case, async: false
  use Jamixir.DBCase
  alias Codec.State.Trie
  alias System.State
  alias Util.Hash
  use StoragePrefix
  import Jamixir.Factory
  import Codec.Encoder
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

    test "get non-existent header" do
      assert Storage.get(Hash.random()) == nil
    end

    test "get latest header when key is empty" do
      Storage.remove("latest_timeslot")
      assert Storage.get_latest_header() == nil
    end
  end

  describe "put and get block" do
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
      epoch = :rand.uniform(100_000)

      [t1, t2] = build_list(2, :ticket_proof, attempt: 0)
      assert {:ok, _} = Storage.put(epoch, t1)
      assert {:ok, _} = Storage.put(epoch, t2)
      assert Storage.get_tickets(epoch) == [t1, t2]
    end

    test "put and get ticket different epochs" do
      e1 = :rand.uniform(100_000)
      e2 = :rand.uniform(100_000)
      [t1, t2] = build_list(2, :ticket_proof, attempt: 0)
      assert {:ok, _} = Storage.put(e1, t1)
      assert {:ok, _} = Storage.put(e2, t2)
      assert Storage.get_tickets(e1) == [t1]
      assert Storage.get_tickets(e2) == [t2]
    end
  end

  describe "put and get segment shard" do
    test "put and get segment shard" do
      erasure_root = Hash.random()
      shard_index = 1
      segment_index = 2
      shard_data = <<1, 2, 3, 4, 5>>

      {:ok, _} = Storage.put_segment_shard(erasure_root, shard_index, segment_index, shard_data)
      assert Storage.get_segment_shard(erasure_root, shard_index, segment_index) == shard_data
    end
  end

  describe "guarantee storage operations" do
    test "put guarantee and fetch get_all" do
      guarantee =
        build(:guarantee,
          work_report: build(:work_report, core_index: 0),
          timeslot: 100,
          credentials: [{0, <<1::512>>}, {1, <<2::512>>}]
        )

      Storage.put(guarantee)

      candidates = Storage.get_guarantees(:pending)
      assert length(candidates) == 1

      candidate = Enum.find(candidates, &(&1.core_index == 0))
      assert candidate.core_index == 0
      assert candidate.timeslot == 100
      assert candidate.work_report_hash == h(e(guarantee.work_report))
    end

    test "put guarantee and fetch work report" do
      guarantee =
        build(:guarantee,
          work_report: build(:work_report, core_index: 1),
          timeslot: 200
        )

      Storage.put(guarantee)

      wr = guarantee.work_report
      encoded_wr = e(wr)
      wr_hash = h(encoded_wr)

      fetched_wr = Storage.get_work_report(wr_hash)
      assert fetched_wr == wr
    end

    test "mark guarantees as included and verify they dont appear in candidates" do
      guarantee1 =
        build(:guarantee,
          work_report: build(:work_report, core_index: 0),
          timeslot: 100
        )

      guarantee2 =
        build(:guarantee,
          work_report: build(:work_report, core_index: 1),
          timeslot: 100
        )

      guarantee3 =
        build(:guarantee,
          work_report: build(:work_report, core_index: 2),
          timeslot: 100
        )

      Storage.put(guarantee1)
      Storage.put(guarantee2)
      Storage.put(guarantee3)

      candidates_before = Storage.get_guarantees(:pending)
      assert length(candidates_before) == 3

      wr1_hash = h(e(guarantee1.work_report))
      wr2_hash = h(e(guarantee2.work_report))
      header_hash = Hash.random()

      Storage.mark_guarantee_included([wr1_hash], header_hash)
      Storage.mark_guarantee_rejected([wr2_hash])

      candidates_after = Storage.get_guarantees(:pending)
      assert length(candidates_after) == 1
      assert hd(candidates_after).core_index == 2
    end
  end
end
