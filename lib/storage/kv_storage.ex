defmodule KVStorage do
  @table_name JamObjects

  def start_link(opts \\ []) do
    with :ok <- init_mnesia(),
         {:ok, _pid} <- PersistStorage.start_link(opts) do
      {:ok, self()}
    end
  end

  def put(key, value) do
    :mnesia.transaction(fn ->
      :mnesia.write({@table_name, key, value})
    end)

    PersistStorage.put(key, value)
    {:ok, key}
  end

  def put(map) when is_map(map) do
    :mnesia.transaction(fn ->
      Enum.each(map, fn {key, value} -> :mnesia.write({@table_name, key, value}) end)
    end)

    PersistStorage.put(map)
    {:ok, Map.keys(map)}
  end

  def get(key) do
    case :mnesia.transaction(fn -> :mnesia.read({@table_name, key}) end) do
      {:atomic, [{@table_name, _key, value}]} ->
        value

      _ ->
        # Not in memory, try disk
        case PersistStorage.get(key) do
          nil ->
            nil

          value ->
            # Async update to memory
            write_fn = fn -> :mnesia.write({@table_name, key, value}) end
            transaction_fn = fn -> :mnesia.transaction(write_fn) end
            Task.start(transaction_fn)

            value
        end
    end
  end

  def remove(key) do
    case :mnesia.transaction(fn -> :mnesia.delete({@table_name, key}) end) do
      {:atomic, :ok} ->
        PersistStorage.delete(key)
        :ok

      {:aborted, {:no_exists, _}} ->
        :ok

      error ->
        {:error, error}
    end
  end

  def remove_all do
    :mnesia.clear_table(@table_name)
    PersistStorage.clear()
  end

  defp init_mnesia do
    :mnesia.create_schema([node()])
    :mnesia.start()

    case :mnesia.create_table(@table_name,
           attributes: [:key, :value],
           record_name: @table_name
         ) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, @table_name}} -> :ok
      error -> {:error, error}
    end
  end
end
