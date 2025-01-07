defmodule QuicServer do
  alias System.Network.CertUtils
  use GenServer

  defstruct [
    :socket,
    # Track our acceptor process
    :acceptor_pid,
    stream_kinds: %{},
    connections: %{}
  ]

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

  @log_id "Server"

  def default_opts, do: @default_opts

  def start_link(port \\ 9999) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  def init(port) do
    {:ok, socket} = :quicer.listen(port, @default_opts)
    IO.puts("Server listening on port #{port}")

    spawn_link(fn ->
      Process.flag(:trap_exit, true)
      {:ok, conn} = :quicer.accept(socket, [], :infinity)
      IO.puts("Server - Connection accepted")
      {:ok, conn} = :quicer.handshake(conn)
      IO.puts("Server - Handshake completed")

      accept_loop(conn)
    end)

    {:ok, socket}
  end

  defp accept_loop(conn) do
    {:ok, stream} = :quicer.accept_stream(conn, [])
    IO.puts("Server - Stream accepted")

    # Handle stream in same process
    receive do
      {:quic, <<kind, data::binary>>, ^stream, _props} ->
        IO.puts("Server - Stream identified as kind: #{kind_name(kind)}")
        response = "echo: #{data}"
        {:ok, _} = :quicer.send(stream, response)
        IO.puts("Server - Sent response: #{response}")

        # For UP streams, keep listening
        if kind < 128 do
          receive_loop(stream)
        end

      other ->
        IO.puts("Server - Unexpected message: #{inspect(other)}")
    after
      5000 ->
        IO.puts("Server - Timeout waiting for stream data")
    end

    accept_loop(conn)  # Keep accepting new streams
  end

  defp receive_loop(stream) do
    receive do
      {:quic, data, ^stream, _props} ->
        response = "echo: #{data}"
        {:ok, _} = :quicer.send(stream, response)
        IO.puts("Server - Sent response: #{response}")
        receive_loop(stream)
    end
  end

  defp kind_name(kind) when kind < 128, do: "UP"
  defp kind_name(_kind), do: "CE"
end
