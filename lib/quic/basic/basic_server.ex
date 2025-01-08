defmodule BasicQuicServer do
  use GenServer
  alias System.Network.CertUtils

  defmodule State do
    defstruct [
      :socket,
      :connection,
      # Track messages per stream
      streams: %{}
    ]
  end

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
    {:ok, %State{socket: socket}}
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
    case :quicer.accept_stream(conn, [{:active, true}], :infinity) do
      {:ok, stream} ->
        IO.puts("Server - Stream accepted: #{inspect(stream)}")
        send(self(), :accept_stream)
        {:noreply, state}

      error ->
        IO.puts("Server - Stream accept error: #{inspect(error)}")
        {:noreply, state}
    end
  end

  def handle_info({:quic, data, stream, _props}, %{streams: streams} = state) do
    buffer = Map.get(streams, stream, <<>>)
    new_buffer = buffer <> data

    case process_message(new_buffer) do
      {:complete, message, _stream_id} ->
        IO.puts("Server received complete message: #{inspect(message)}")
        send_result = :quicer.send(stream, message)
        IO.puts("Server - Send result: #{inspect(send_result)}")
        # :quicer.shutdown_stream(stream, :send)
        {:noreply, %{state | streams: Map.delete(streams, stream)}}

      {:incomplete, partial_buffer} ->
        IO.puts("Server - stream: #{inspect(stream)}")
        IO.puts("Server - partial_buffer: #{inspect(partial_buffer)}")
        {:noreply, %{state | streams: Map.put(streams, stream, partial_buffer)}}
    end

    {:noreply, state}
  end

  def handle_info({:quic, :stream_closed, stream, _props}, state) do
    IO.puts("Server - Stream #{inspect(stream)} closed")
    {:noreply, %{state | streams: Map.delete(state.streams, stream)}}
  end

  defp process_message(<<stream_id::8, length::32-little, message::binary-size(length)>>) do
    {:complete, message, stream_id}
  end

  defp process_message(rest) do
    {:incomplete, rest}
  end
end
