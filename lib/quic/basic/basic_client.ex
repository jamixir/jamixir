defmodule BasicQuicClient do
  use GenServer
  @call_default_config [host: ~c"localhost", port: 9999, timeout: 5_000]

  def start_link(config \\ []) do
    conf = Keyword.merge(@call_default_config, config)
    GenServer.start_link(__MODULE__, conf, name: __MODULE__)
  end

  def send_and_wait(pid, message) do
    GenServer.call(pid, {:send_and_wait, message}, 5_000)
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
        {:ok, conn}

      error ->
        IO.puts("Client connection failed: #{inspect(error)}")
        {:stop, error}
    end
  end

  def handle_call({:send_and_wait, message}, _from, conn) do
    {:ok, stream} = :quicer.start_stream(conn, [{:stream_id, 128}])
    IO.puts("Client - Stream started: #{inspect(stream)}")

    length = byte_size(message)
    payload = <<length::32-little, message::binary>>
    random_number = Enum.random(128..255)
    :quicer.send(stream, <<random_number>>)
    :quicer.send(stream, payload)

    receive do
      {:quic, response, ^stream, _props} ->
        IO.puts("Client received response: #{inspect(response)}")
        {:reply, {:ok, {:ok, response}}, conn}

      {:quic, :stream_closed, ^stream, _props} ->
        IO.puts("Client - Stream closed by server")
        {:reply, :ok, conn}
    after
      5_000 ->
        IO.puts("Client timed out waiting for response")
        {:reply, {:error, :timeout}, conn}
    end
  end
end
