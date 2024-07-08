defmodule Storage do
  
  def new do
    %{}
  end

  def put(storage, key, value) do
    Map.put(storage, key, value)
  end

  def get(storage, key) do
    Map.get(storage, key)
  end

  def delete(storage, key) do
    Map.delete(storage, key)
  end
end