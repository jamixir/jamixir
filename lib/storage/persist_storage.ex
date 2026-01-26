defmodule PersistStorage do
  use GenServer
  @compact_interval :timer.minutes(5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def put(key, value) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:put, key, value})
    end

    {:ok, key}
  end

  def put(map) when is_map(map) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:put_map, map})
    end

    {:ok, Map.keys(map)}
  end

  @doc """
  Sync call to ensure all pending writes are processed.
  This helps prevent the write queue from growing too large.
  """
  def sync do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :sync, 60_000)
    end

    :ok
  end

  def get(key) do
    if Process.whereis(__MODULE__) do
      # Longer timeout because writes are async (cast) and can build up a queue
      # that the read (call) must wait behind
      GenServer.call(__MODULE__, {:get, key}, 30_000)
    end
  rescue
    _ -> nil
  end

  def delete(key) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:delete, key})
    end

    :ok
  end

  def clear do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, :clear)
    end

    :ok
  end

  @impl true
  def init(opts) do
    if Jamixir.config()[:test_env] do
      node_id = "test_#{System.pid()}"
      init_with_simple_paths(opts, node_id)
    else
      node_id = Jamixir.NodeIdentity.node_id()
      init_with_node_isolation(opts, node_id)
    end
  end

  defp init_with_node_isolation(opts, node_id) do
    case Keyword.get(opts, :persist) do
      true ->
        db_path = get_db_path()
        File.mkdir_p!(db_path)

        case CubDB.start_link(
               data_dir: db_path,
               name: nil,
               auto_compact: false
             ) do
          {:ok, db} ->
            schedule_compaction()
            {:ok, %{db: db, persist: true, ops_count: 0, node_id: node_id}}

          error ->
            {:stop, error}
        end

      false ->
        # Use node-specific temporary directory
        tmp_dir = System.tmp_dir!() |> Path.join("jamixir") |> Path.join(node_id)
        File.mkdir_p!(tmp_dir)

        case CubDB.start_link(
               data_dir: tmp_dir,
               name: nil,
               auto_compact: false
             ) do
          {:ok, db} ->
            {:ok, %{db: db, persist: false, ops_count: 0, node_id: node_id}}

          error ->
            {:stop, error}
        end
    end
  end

  defp init_with_simple_paths(opts, node_id) do
    case Keyword.get(opts, :persist) do
      true ->
        # Use simple persistent directory for tests
        db_path = Path.join(System.tmp_dir!(), "jamixir_persist_test")
        File.mkdir_p!(db_path)

        case CubDB.start_link(
               data_dir: db_path,
               name: nil,
               auto_compact: false
             ) do
          {:ok, db} ->
            schedule_compaction()
            {:ok, %{db: db, persist: true, ops_count: 0, node_id: node_id}}

          error ->
            {:stop, error}
        end

      false ->
        # Use simple temporary directory for tests
        tmp_dir = Path.join(System.tmp_dir!(), "jamixir_temp_test")
        File.mkdir_p!(tmp_dir)

        case CubDB.start_link(
               data_dir: tmp_dir,
               name: nil,
               auto_compact: false
             ) do
          {:ok, db} ->
            {:ok, %{db: db, persist: false, ops_count: 0, node_id: node_id}}

          error ->
            {:stop, error}
        end
    end
  end

  defp get_db_path do
    case Application.get_env(:jamixir, :database_path) do
      # No CLI  override → node-isolated storage
      nil ->
        Jamixir.NodeIdentity.node_dir()
        |> Path.join("persistent")

      # User explicitly set --database-path
      path ->
        path
        |> Path.expand()
    end
  end

  @impl true
  def handle_cast({:put, key, value}, %{db: db, persist: true} = state) do
    CubDB.put(db, key, value)
    {:noreply, %{state | ops_count: state.ops_count + 1}}
  end

  def handle_cast({:put_map, map}, %{db: db, persist: true} = state) do
    CubDB.put_multi(db, map)
    {:noreply, %{state | ops_count: state.ops_count + 1}}
  end

  def handle_cast({:delete, key}, %{db: db, persist: true} = state) do
    CubDB.delete(db, key)
    {:noreply, state}
  end

  def handle_cast(:clear, %{db: db, persist: true} = state) do
    CubDB.clear(db)
    {:noreply, state}
  end

  def handle_cast(_, %{persist: false} = state), do: {:noreply, state}

  @impl true
  def handle_call({:get, key}, _from, %{db: db, persist: true} = state) do
    {:reply, CubDB.get(db, key), state}
  end

  def handle_call(:sync, _from, state) do
    # This call ensures all pending casts have been processed
    {:reply, :ok, state}
  end

  def handle_call(_, _from, %{persist: false} = state) do
    {:reply, nil, state}
  end

  @impl true
  def handle_info(:compact, %{persist: true, db: db} = state) do
    CubDB.compact(db)
    schedule_compaction()
    {:noreply, %{state | ops_count: 0}}
  end

  def handle_info(:compact, state), do: {:noreply, state}

  defp schedule_compaction do
    Process.send_after(self(), :compact, @compact_interval)
  end

  @impl true
  def terminate(_reason, %{db: db}) when not is_nil(db) do
    try do
      GenServer.stop(db, :normal, 5000)
    rescue
      _ -> :ok
    end
  end

  def terminate(_reason, _state), do: :ok

  def stop do
    if pid = Process.whereis(__MODULE__) do
      GenServer.stop(pid, :normal, 5000)
    end
  end
end
