defmodule StorageTest do
  use ExUnit.Case

  # Existing tests

  test "store/2 stores the value in the storage" do
    storage = Storage.new()
    {:ok, storage2 } = Storage.store(storage, :key, "value1")
    assert Storage.get(storage2, :key) == { :ok, "value1" }
  end

  test "store/2 overwrites the existing value in the storage" do
    storage = Storage.new()
    {:ok, storage2 } = Storage.store(storage, :key, "value1")
    {:ok, storage3 } = Storage.store(storage2, :key, "value2")
    assert Storage.get(storage3, :key) == {:ok, "value2"}
  end

  # New tests

  test "store/2 returns the updated storage" do
    storage = Storage.new()
    {:ok, updated_storage} = Storage.store(storage, :key, "value")
    assert updated_storage == %{key: "value"}
  end

  test "get/2 returns nil if the key does not exist in the storage" do
    storage = Storage.new()
    assert Storage.get(storage, :non_existing_key) == {:error, "Key not found"}
  end

  test "get/2 returns the value associated with the key in the storage" do
    storage = Storage.new()
    {:ok, storage2 } = Storage.store(storage, :key, "value")
    assert Storage.get(storage2, :key) == {:ok, "value"}
  end

  test "remove/2 removes the key and its associated value from the storage" do
    storage = Storage.new()
    {:ok, storage2 } = Storage.store(storage, :key, "value")
    {:ok, storage3 } = Storage.remove(storage2, :key)
    assert Storage.get(storage3, :key) == {:error, "Key not found"}
  end
end