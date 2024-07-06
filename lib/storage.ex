defmodule Storage do
  
  def new do
    %{}
  end

  def store(storage, key, value) do
    new_storage = Map.put(storage, key, value)
    {:ok, new_storage}
  end

  def get(storage, key) do
    case Map.get(storage, key) do
      nil -> {:error, "Key not found"}
      value -> {:ok, value}
    end
  end

  def remove(storage, key) do
    new_storage = Map.delete(storage, key)
    {:ok, new_storage}
  end
end