defmodule PersistStorageTest do
  use ExUnit.Case

  setup do
    # Stop any existing PersistStorage process
    if pid = Process.whereis(PersistStorage) do
      GenServer.stop(pid)
    end

    # Stop any existing CubDB process
    if pid = Process.whereis(:cubdb) do
      GenServer.stop(pid)
    end

    {:ok, pid} = PersistStorage.start_link(persist: true)

    on_exit(fn ->
      if Process.alive?(pid), do: PersistStorage.stop()
    end)

    :ok
  end

  test "basic persistence operations" do
    PersistStorage.put("key1", "value1")
    # Wait for async write
    Process.sleep(100)
    assert PersistStorage.get("key1") == "value1"
  end

  test "multi-put operations" do
    map = %{"key1" => "value1", "key2" => "value2"}
    PersistStorage.put(map)
    Process.sleep(100)

    assert PersistStorage.get("key1") == "value1"
    assert PersistStorage.get("key2") == "value2"
  end

  test "persistence can be disabled" do
    PersistStorage.stop()
    {:ok, _} = PersistStorage.start_link(persist: false)

    PersistStorage.put("key1", "value1")
    assert PersistStorage.get("key1") == nil
  end

  test "delete operation" do
    PersistStorage.put("key1", "value1")
    Process.sleep(100)

    PersistStorage.delete("key1")
    Process.sleep(100)

    assert PersistStorage.get("key1") == nil
  end

  test "clear operation" do
    map = %{"key1" => "value1", "key2" => "value2"}
    PersistStorage.put(map)
    Process.sleep(100)

    PersistStorage.clear()
    Process.sleep(100)

    assert PersistStorage.get("key1") == nil
    assert PersistStorage.get("key2") == nil
  end
end
