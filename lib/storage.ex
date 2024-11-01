defmodule Storage do
  alias Util.Hash

  @table_name JamObjects

  def start_link do
    init_mnesia()
  end

  def put(object) when is_struct(object) do
    put(Encodable.encode(object))
  end

  def put(list) when is_list(list) do
    for o <- list, do: put(o)
  end

  def put(blob) when is_binary(blob) do
    case :mnesia.transaction(fn -> :mnesia.write({@table_name, Hash.default(blob), blob}) end) do
      {:atomic, :ok} -> :ok
      error -> {:error, error}
    end
  end

  def get(hash, module) do
    case get(hash) do
      nil ->
        nil

      blob ->
        {h, _} = module.decode(blob)
        h
    end
  end

  def get(hash) do
    case :mnesia.transaction(fn -> :mnesia.read({@table_name, hash}) end) do
      {:atomic, [{@table_name, _hash, blob}]} -> blob
      {:atomic, []} -> nil
      {:aborted, {:no_exists, _}} -> nil
      _ -> nil
    end
  end

  def delete(hash) do
    :mnesia.transaction(fn -> :mnesia.delete({@table_name, hash}) end)
    :ok
  end

  defp init_mnesia do
    :mnesia.create_schema([node()])
    :mnesia.start()

    case :mnesia.create_table(@table_name,
           attributes: [:hash, :blob],
           record_name: @table_name
         ) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, @table_name}} -> :ok
      error -> {:error, error}
    end
  end
end
