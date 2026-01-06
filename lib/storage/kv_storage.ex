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
    # Only enforce strict Mnesia directory requirements in prod/tiny runtime environments
    mnesia_dir = Application.get_env(:mnesia, :dir)

    mnesia_dir =
      case Mix.env() do
        env when env in [:prod, :tiny] ->
          if is_nil(mnesia_dir) do
            raise """
            Mnesia directory not configured. This indicates a startup order problem.

            Storage isolation requires Mnesia :dir to be set in Commands.Run
            before Application.ensure_all_started(:jamixir) is called.
            """
          end
          mnesia_dir

        _ ->
          # In test/dev environments, use a default directory if not set
          mnesia_dir || Path.join(System.tmp_dir!(), "jamixir_mnesia_#{Mix.env()}")
      end

    # Ensure directory exists
    File.mkdir_p!(mnesia_dir)

    # Stop Mnesia if it's already running (shouldn't happen, but safety check)
    :mnesia.stop()

    # create schema if it doesn't exist
    schema_file = Path.join(mnesia_dir, "schema.DAT")
    unless File.exists?(schema_file) do
      :mnesia.create_schema([node()])
    end

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
