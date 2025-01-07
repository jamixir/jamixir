defmodule BasicQuicServer do
  use GenServer
  alias System.Network.CertUtils

  defstruct [:socket, :connection, streams: %{}]

  @fixed_opts [
    alpn: [~c"jamnp-s/V/H"],
    peer_bidi_stream_count: 100,
    peer_unidi_stream_count: 100,
    versions: [:"tlsv1.3"],
    verify: :none
  ]

  @default_opts [
    certfile: ~c"#{CertUtils.certfile()}",
    keyfile: ~c"#{CertUtils.keyfile()}"
  ] ++ @fixed_opts

  def start_link(port \\ 9999) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  def init(port) do
    {:ok, socket} = :quicer.listen(port, @default_opts)
    IO.puts("Server listening on port #{port}")
    send(self(), :accept_connection)
    {:ok, %__MODULE__{socket: socket}}
  end

  def handle_info(:accept_connection, %{socket: socket} = state) do
    case :quicer.accept(socket, [], :infinity) do
      {:ok, conn} ->
        IO.puts("Server - Connection accepted")
        {:ok, conn} = :quicer.handshake(conn)
        IO.puts("Server - Handshake completed")
        send(self(), :accept_stream)
        {:noreply, %{state | connection: conn}}

      error ->
        IO.puts("Server - Accept error: #{inspect(error)}")
        send(self(), :accept_connection)
        {:noreply, state}
    end
  end

  def handle_info(:accept_stream, %{connection: conn} = state) do
    case :quicer.accept_stream(conn, [{:active, false}], :infinity) do
      {:ok, stream} ->
        IO.puts("Server - Stream accepted: #{inspect(stream)}")
        spawn(fn -> wait_for_message(stream) end)
        send(self(), :accept_stream)
        {:noreply, state}

      error ->
        IO.puts("Server - Stream accept error: #{inspect(error)}")
        {:noreply, state}
    end
  end

  defp wait_for_message(stream) do
    case :quicer.recv(stream, 0) do
      {:ok, <<_id::8, length::32-little, message::binary-size(length)>>} ->
        IO.puts("Server - Complete message received: #{inspect(message)}")
        :quicer.send(stream, message)
        :quicer.shutdown_stream(stream, :send)

      {:error, :closed} ->
        IO.puts("Server - Stream closed by peer")

      {:error, reason} ->
        IO.puts("Server - Error: #{inspect(reason)}")

      _ ->
        wait_for_message(stream)
    end
  end
end
