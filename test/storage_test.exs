defmodule StorageTest do
  use ExUnit.Case

  # Existing tests
  test "store/2 stores the value in the storage" do
    storage = Storage.new()
    storage2 = Storage.put(storage, :key, "value1")
    assert Storage.get(storage2, :key) == "value1"
  end

  test "store/2 overwrites the existing value in the storage" do
    storage = Storage.new()
    storage2 = Storage.put(storage, :key, "value1")
    storage3 = Storage.put(storage2, :key, "value2")
    assert Storage.get(storage3, :key) == "value2"
  end

  # New tests

  test "store/2 returns the updated storage" do
    storage = Storage.new()
    updated_storage = Storage.put(storage, :key, "value")
    assert updated_storage == %{key: "value"}
  end

  test "get/2 returns nil if the key does not exist in the storage" do
    storage = Storage.new()
    assert Storage.get(storage, :non_existing_key) == nil
  end

  test "get/2 returns the value associated with the key in the storage" do
    storage = Storage.new()
    storage2 = Storage.put(storage, :key, "value")
    assert Storage.get(storage2, :key) == "value"
  end

  test "delete/2 removes the key and its associated value from the storage" do
    storage = Storage.new()
    storage2 = Storage.put(storage, :key, "value")
    storage3 = Storage.delete(storage2, :key)
    assert Storage.get(storage3, :key) == nil
  end
end
