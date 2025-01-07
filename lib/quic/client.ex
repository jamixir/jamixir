defmodule QuicClient do
  use GenServer
  require Logger
  alias QuicServer

  defstruct [
    :connection,
    # Optional UP stream
    :up_stream,
    # Map of stream_id => stream_ref
    ce_streams: %{},
    # Track next available ID
    next_ce_id: 128,
    connection_state: :disconnected
  ]

  @log_id "Client"
  # UP streams start at 0
  @up_stream_id 0
  # CE streams start at 128
  @ce_stream_base_id 128
  @call_default_config [host: ~c"localhost", port: 9999, timeout: 60_000]

  def start_link(config \\ []) do
    conf = Keyword.merge(@call_default_config, config)
    GenServer.start_link(__MODULE__, conf, name: __MODULE__)
  end

  def send_ce(message) do
    GenServer.call(__MODULE__, {:send_ce, message})
  end

  def send_up(message) do
    GenServer.call(__MODULE__, {:send_up, message})
  end

  def start_up_stream do
    GenServer.call(__MODULE__, :start_up_stream)
  end

  def init(conf) do
    IO.puts("Client connecting...")

    case :quicer.connect(
           conf[:host],
           conf[:port],
           QuicServer.default_opts(),
           conf[:timeout]
         ) do
      {:ok, conn} ->
        IO.puts("Client connected")

        {:ok,
         %__MODULE__{
           connection: conn,
           connection_state: :connected
         }}

      error ->
        IO.puts("Failed to connect: #{inspect(error)}")
        {:stop, error}
    end
  end

  # Connection event handlers
  def handle_info({:quic, :connected, connection}, state) do
    IO.puts("#{@log_id} - Connected successfully!")
    {:noreply, %{state | connection_state: :connected}}
  end

  def handle_info({:quic, :connection_closed, reason}, state) do
    IO.puts("#{@log_id} - Connection closed: #{inspect(reason)}")
    {:noreply, %{state | connection_state: :disconnected}}
  end

  def handle_info({:quic, :streams_available, _conn, streams}, state) do
    IO.puts("#{@log_id} - Streams available: #{inspect(streams)}")
    {:noreply, state}
  end

  # Catch-all for unexpected messages
  def handle_info(msg, state) do
    IO.puts("#{@log_id} - Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  def handle_call({:send_ce, message}, _from, %{connection: conn, ce_streams: streams} = state) do
    stream_id = find_next_ce_id(streams)
    IO.puts("#{@log_id} - Sending CE message to stream #{stream_id}")

    {:ok, stream} = :quicer.start_stream(conn, [{:stream_id, stream_id}])
    # Send stream kind identifier
    # log stream object
    IO.puts("#{@log_id} - Sending stream kind identifier #{stream_id}")
    {:ok, _} = :quicer.send(stream, <<stream_id>>)
    IO.puts("#{@log_id} - Sending CE message #{message}")
    {:ok, _} = :quicer.send(stream, message)

    # Store stream in state
    state = %{state | ce_streams: Map.put(streams, stream, message)}

    receive do
      {:quic, data, ^stream, _props} ->
        IO.puts("#{@log_id} - CE response received: #{inspect(data)}")
        # Remove stream from state after response
        state = %{state | ce_streams: Map.delete(streams, stream)}
        {:reply, {:ok, data}, state}
    # after
    #   5000 ->
    #     state = %{state | ce_streams: Map.delete(streams, stream)}
    #     {:reply, {:error, :timeout}, state}
    end
  end

  def handle_call({:send_up, message}, _from, %{up_stream: nil} = state) do
    case handle_call(:start_up_stream, _from, state) do
      {:reply, {:ok, _}, new_state} -> handle_call({:send_up, message}, _from, new_state)
      {:reply, error, state} -> {:reply, error, state}
    end
  end

  def handle_call({:send_up, message}, _from, %{up_stream: stream} = state) do
    case :quicer.send(stream, message) do
      {:ok, _} ->
        receive do
          {:quic, data, ^stream, _props} ->
            IO.puts("UP response received: #{inspect(data)}")
            {:reply, {:ok, data}, state}
        after
          5000 ->
            {:reply, {:error, :timeout}, state}
        end

      error ->
        {:reply, error, state}
    end
  end

  # Private functions
  defp open_up_stream(conn) do
    case :quicer.start_stream(conn, [{:stream_id, @up_stream_id}]) do
      {:ok, stream} ->
        # Send stream kind identifier
        :ok = :quicer.send(stream, <<@up_stream_id>>)
        {:ok, stream}

      error ->
        error
    end
  end

  defp find_next_ce_id(streams) do
    used_ids = Map.keys(streams)

    # Find first available ID starting from base
    Stream.iterate(@ce_stream_base_id, &(&1 + 1))
    |> Enum.find(fn id -> id not in used_ids end)
  end
end
