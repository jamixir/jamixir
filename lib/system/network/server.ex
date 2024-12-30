defmodule System.Network.Server do
  alias System.Network.{Calls, CertUtils}
  require Logger
  use Codec.Decoder
  use Codec.Encoder

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

    code =
      receive do
        {:quic, <<stream_kind::8>>, ^stream, _props} ->
          Logger.info("Executing call #{stream_kind}")
          stream_kind

        other ->
          Logger.info("unexpected message Received: #{inspect(other)}")
          :invalid
      end

    if code == :invalid do
      Logger.info("Invalid code received: #{code}. Closing stream.")
      :quicer.shutdown_stream(stream)
    else
      {:ok, bin} = receive_message(stream)
      Logger.info("Executing call #{code}")
      result = Calls.call(code, bin)
      Logger.info("Sending response: #{inspect(result)} of size #{byte_size(result)}")
      send_message(stream, result)
      handle_stream(stream)
    end
  end

  def send_message(stream, message) do
    Logger.info("Sending message: #{inspect(message)}")
    :quicer.send(stream, e_le(byte_size(message), 4))
    :quicer.send(stream, message)
  end

  def receive_message(stream) do
    {:ok, {message_size, first_bytes}} =
      receive do
        {:quic, bin, ^stream, _props} ->
          <<m_size::binary-size(4), first_bytes::binary>> = bin
          Logger.info("Received #{byte_size(bin)} bytes: #{inspect(bin)}")
          {:ok, {de_le(m_size, 4), first_bytes}}

        x ->
          Logger.error("Unexpected message: #{inspect(x)}")
          {:error, :unknown_message}
      end

    Logger.info("Receiving message of size #{message_size}")

    {:ok, message_bytes} =
      Enum.reduce_while(1..message_size, first_bytes, fn _, acc ->
        if byte_size(acc) >= message_size do
          {:halt, {:ok, acc}}
        else
          receive do
            {:quic, bin, ^stream, _props} ->
              {:cont, acc <> bin}

            x ->
              Logger.error("Unexpected message: #{inspect(x)}")
              {:halt, {:error, :unknown_message}}
          end
        end
      end)

    Logger.info("Received message: #{inspect(message_bytes)}")

    {:ok, message_bytes}
  rescue
    error ->
      Logger.error("Error receiving message: #{inspect(error)}")
      :quicer.shutdown_stream(stream)
      error
  end
end
