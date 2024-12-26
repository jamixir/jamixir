defmodule System.Network.Server do
  alias System.Network.CertUtils
  alias System.Network.Calls
  require Logger

  @doc """
  Starts a QUIC server.

  Accepts a `cert_path` for the server certificate, a `key_path` for the server private key, and a `port`.

  It starts a new `JamnpS.Server` task that handles QUIC connections.
  """
  @fixed_opts [
    alpn: [~c"jamnp-s/V/H"],
    peer_bidi_stream_count: 10,
    peer_unidi_stream_count: 1,
    versions: [:"tlsv1.3"],
    verify: :none
  ]

  @default_opts [
                  certfile: ~c"#{CertUtils.certfile()}",
                  keyfile: ~c"#{CertUtils.keyfile()}"
                ] ++ @fixed_opts

  @default_port 9999
  def fixed_opts, do: @fixed_opts
  def default_opts, do: @default_opts

  def start_server(port \\ @default_port, opts \\ @default_opts) do
    {:ok, socket} = :quicer.listen(port, opts)
    Logger.info("Listening on port #{port}...")
    loop(socket)
  rescue
    error ->
      IO.puts("Error starting server: #{inspect(error)}")
      error
  end

  defp loop(listen_socket) do
    case :quicer.accept(listen_socket, [keep_alive_interval_ms: 1_000], :infinity) do
      {:ok, conn} ->
        Logger.info("New connection accepted: #{inspect(conn)}")
        handle_connection(conn)

      {:error, reason} ->
        Logger.error("Error accepting connection: #{inspect(reason)}")
    end

    # Continue listening for new connections
    loop(listen_socket)
  end

  defp handle_connection(conn) do
    case :quicer.handshake(conn) do
      {:ok, conn} ->
        Logger.info("Handshake successful: #{inspect(conn)}")
        spawn(fn -> handle_connection_loop(conn) end)

      {:error, reason} ->
        Logger.error("Handshake failed: #{inspect(reason)}")
    end
  end

  defp handle_connection_loop(conn) do
    Logger.info("Waiting for new stream...")

    case :quicer.accept_stream(conn, [], :infinity) do
      {:ok, stream} ->
        Logger.info("New stream accepted: #{inspect(stream)}")
        spawn(fn -> handle_connection_loop(conn) end)
        handle_stream(stream)

      {:error, reason} ->
        Logger.error("Error accepting stream: #{inspect(reason)}")
    end
  end

  defp handle_stream(stream) do
    Logger.info("Waiting for message on stream: #{inspect(stream)}")

    receive do
      {:quic, message, ^stream, _props} ->
        <<code::8, bin::binary>> = message
        Logger.info("Executing call #{code}")
        result = Calls.call(code, bin)
        Logger.info("Sending response: #{inspect(result)} of size #{byte_size(result)}")
        :quicer.send(stream, result)
        handle_stream(stream)

      other ->
        Logger.info("unexpected message Received: #{inspect(other)}")
    end
  end
end
