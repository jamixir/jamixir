defmodule Jamixir.Node do
  use GenServer
  @persist_file "jamixir_state.json"

  # Start the GenServer and register it under a global name
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Public API
  def load_state(path), do: GenServer.call(__MODULE__, {:load_state, path})
  def save_state(path), do: GenServer.call(__MODULE__, {:save_state, path})
  def add_block(block), do: GenServer.call(__MODULE__, {:add_block, block})
  def inspect_state(), do: GenServer.call(__MODULE__, :inspect_state)
  def inspect_state(key), do: GenServer.call(__MODULE__, {:inspect_state, key})
  def stop(), do: GenServer.call(__MODULE__, :stop)

  # Callbacks
  @impl true
  def init(_) do
    {:ok, []}
  end

  @impl true
  def handle_call({:load_state, path}, _from, _state) do
    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, json_data} ->
            state = System.State.from_json(json_data |> Utils.atomize_keys())
            # Persist the newly loaded state
            File.write!(@persist_file, Jason.encode!(json_data))
            {:reply, :ok, state}

          error ->
            {:reply, error, nil}
        end

      error ->
        {:reply, error, nil}
    end
  end

  @impl true
  def handle_call({:save_state, path}, _from, state) do
    case File.write(path, Jason.encode!(state)) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:add_block, block}, _from, state) do
    {:reply, :ok, [block | state]}
  end

  @impl true
  def handle_call(:inspect_state, _from, nil) do
    {:reply, {:ok, :no_state}, nil}
  end

  @impl true
  def handle_call({:inspect_state, key}, _from, state) when is_map(state) do
    key_atom = String.to_existing_atom(key)

    case Map.fetch(state, key_atom) do
      {:ok, value} -> {:reply, {:ok, value}, state}
      :error -> {:reply, {:error, :key_not_found}, state}
    end
  end

  @impl true
  def handle_call(:inspect_state, _from, state) when is_map(state) do
    # Just return the keys when no specific key is requested
    {:reply, {:ok, Map.keys(state)}, state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    # Just stop the node directly
    System.stop(0)
    {:stop, :normal, :ok, state}
  end
end
