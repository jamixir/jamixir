defmodule KVStorage do
  @table_name JamObjects
  use Codec.Encoder

  def start_link do
    case init_mnesia() do
      :ok ->
        {:ok, self()}

      error ->
        error
    end
  end


  def put(key, value) do
    :mnesia.transaction(fn ->
      :mnesia.write({@table_name, key, value})
    end)

    {:ok, key}
  end

  def put(map) when is_map(map) do
    :mnesia.transaction(fn ->
      Enum.each(map, fn {key, value} -> :mnesia.write({@table_name, key, value}) end)
    end)

    {:ok, Map.keys(map)}
  end

  def put(data) when is_binary(data) do
    put(Util.Hash.default(data), data)
  end

  def get(key) do
    case :mnesia.transaction(fn -> :mnesia.read({@table_name, key}) end) do
      {:atomic, [{@table_name, _key, value}]} -> value
      {:atomic, []} -> nil
      {:aborted, {:no_exists, _}} -> nil
      _ -> nil
    end
  end

  def get(key, module) do
    case get(key) do
      nil ->
        nil

      blob ->
        {decoded, _rest} = module.decode(blob)
        decoded
    end
  end

  def remove(key) do
    case :mnesia.transaction(fn -> :mnesia.delete({@table_name, key}) end) do
      {:atomic, :ok} -> :ok
      {:aborted, {:no_exists, _}} -> :ok
      error -> {:error, error}
    end
  end

  def remove_all do
    :mnesia.clear_table(@table_name)
  end

  # Private Functions
  # Private Functions
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
