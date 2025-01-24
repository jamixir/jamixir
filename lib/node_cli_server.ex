defmodule Jamixir.NodeCLIServer do
  use GenServer
  require Logger

  # Client API
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def add_block(block_binary), do: GenServer.call(__MODULE__, {:add_block, block_binary})
  def inspect_state, do: GenServer.call(__MODULE__, :inspect_state)
  def inspect_state(key), do: GenServer.call(__MODULE__, {:inspect_state, key})
  def load_state(path), do: GenServer.call(__MODULE__, {:load_state, path})

  # Server Callbacks
  @impl true
  def init(_) do
    init_storage()
  end

  defp init_storage do
    case Storage.start_link(persist: true) do
      {:ok, _} ->
        Logger.info("Storage initialized")
        {:ok, nil}

      error ->
        Logger.error("Failed to initialize storage: #{inspect(error)}")
        {:stop, error}
    end
  end

  @impl true
  def handle_call({:add_block, block_binary}, _from, _state) do
    case Jamixir.Node.add_block(block_binary) do
      :ok -> {:reply, :ok, nil}
      {:error, reason} -> {:reply, {:error, reason}, nil}
    end
  end

  @impl true
  def handle_call(:inspect_state, _from, _state) do
    case Jamixir.Node.inspect_state() do
      {:ok, keys} -> {:reply, {:ok, keys}, nil}
      error -> {:reply, error, nil}
    end
  end

  @impl true
  def handle_call({:inspect_state, key}, _from, _state) do
    case Jamixir.Node.inspect_state(key) do
      {:ok, value} -> {:reply, {:ok, value}, nil}
      error -> {:reply, error, nil}
    end
  end

  @impl true
  def handle_call({:load_state, path}, _from, _state) do
    case Jamixir.Node.load_state(path) do
      :ok -> {:reply, :ok, nil}
      error -> {:reply, error, nil}
    end
  end
end
