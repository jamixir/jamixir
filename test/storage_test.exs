defmodule StorageConstantsMock do
  def max_age, do: 7
end

defmodule StorageTest do
  use ExUnit.Case
  alias Block.Header
  alias Util.Hash
  alias Codec.Encoder

  setup_all do
    Application.put_env(:jamixir, Constants, StorageConstantsMock)
    on_exit(fn -> Application.delete_env(:jamixir, Constants) end)
    :ok
  end

  setup do
    Storage.start_link()
    :mnesia.clear_table(Storage.table_name())
    :ok
  end

  test "put stores and overwrites values" do
    header1 = %Header{timeslot: 1, parent_hash: <<0::256>>}
    header2 = %Header{timeslot: 2, parent_hash: <<0::256>>}

    assert {:ok, hash1} = Storage.put(header1)
    assert [{_, {1, ^hash1}, ^header1}] = :mnesia.dirty_read(Storage.table_name(), {1, hash1})

    assert {:ok, hash2} = Storage.put(header2)
    assert [{_, {2, ^hash2}, ^header2}] = :mnesia.dirty_read(Storage.table_name(), {2, hash2})

    assert hash1 == Hash.default(Encoder.encode(header1))
    assert hash2 == Hash.default(Encoder.encode(header2))
  end

  test "get_parent returns parent or error" do
    {:ok, hash1} = Storage.put( %Header{timeslot: 1, parent_hash: <<0::256>>})

    assert {:ok, %Header{timeslot: 1}} = Storage.get_parent(%Header{timeslot: 2, parent_hash: hash1})
    assert {:error, "Parent header not found"} = Storage.get_parent(%Header{timeslot: 3, parent_hash: "non_existing"})
  end

  test "get_latest returns latest key or nil" do
    assert is_nil(Storage.get_latest())

    header1 = %Header{timeslot: 1, parent_hash: <<0::256>>}
    header2 = %Header{timeslot: 2, parent_hash: <<0::256>>}

    {:ok, _hash1} = Storage.put(header1)
    {:ok, hash2} = Storage.put(header2)

    assert {2, ^hash2} = Storage.get_latest()
  end

  test "clean_up_old_headers removes oldest headers" do
    Enum.each(1..Constants.max_age(), fn i ->
      header = %Header{timeslot: i, parent_hash: <<i::256>>}
      {:ok, _} = Storage.put(header)
    end)

    extra_header = %Header{timeslot: Constants.max_age() + 1, parent_hash: <<(Constants.max_age() + 1)::256>>}
    {:ok, extra_hash} = Storage.put(extra_header)

    assert :mnesia.table_info(Storage.table_name(), :size) == Constants.max_age()
    assert :mnesia.dirty_read(Storage.table_name(), {1, :_}) == []
    assert :mnesia.dirty_read(Storage.table_name(), {Constants.max_age() + 1, extra_hash}) != []
    assert Storage.get_latest() == {Constants.max_age() + 1, extra_hash}
  end

  test "exists? returns true for existing hash and false for non-existing" do
    header = %Header{timeslot: 1, parent_hash: <<0::256>>}
    {:ok, hash} = Storage.put(header)

    assert Storage.exists?(hash) == true
    assert Storage.exists?("non_existing_hash") == false
  end
end
