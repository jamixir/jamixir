defmodule PersistStorage do
  use GenServer
  @db_path "db"
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

  def get(key) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:get, key})
    end
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
    case Keyword.get(opts, :persist) do
      true ->
        File.mkdir_p!(@db_path)

        case CubDB.start_link(
               data_dir: @db_path,
               name: :cubdb,
               auto_compact: false
             ) do
          {:ok, db} ->
            schedule_compaction()
            {:ok, %{db: db, persist: true, ops_count: 0}}

          error ->
            {:stop, error}
        end

      false ->
        {:ok, %{db: nil, persist: false, ops_count: 0}}
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

  def stop do
    if pid = Process.whereis(__MODULE__) do
      GenServer.stop(pid)
    end
  end
end
