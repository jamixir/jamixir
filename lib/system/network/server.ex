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
    peer_bidi_stream_count: 100,
    peer_unidi_stream_count: 100,
    versions: [:"tlsv1.3"],
    verify: :none
  ]

  @default_opts [
                  certfile: ~c"#{CertUtils.certfile()}",
                  keyfile: ~c"#{CertUtils.keyfile()}"
                ] ++ @fixed_opts

  @default_port 9999
  @connection_pool_size 10

  def fixed_opts, do: @fixed_opts
  def default_opts, do: @default_opts

  def start_server(port \\ @default_port, opts \\ @default_opts) do
    {:ok, socket} = :quicer.listen(port, opts)
    Logger.info("Listening on port #{port}...")

    # open listening sockets
    for _ <- 1..@connection_pool_size, do: spawn(fn -> loop(socket) end)
    # a last one to keep the main process alive
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
        handle_stream(stream)
        handle_connection_loop(conn)

      {:error, :closed} ->
        nil

      {:error, reason} ->
        Logger.error("Error accepting stream: #{inspect(reason)}")
    end
  end

  defp handle_stream(stream) do
    Logger.info("Waiting for message on stream: #{inspect(stream)}")

    case read_code_and_message(stream) do
      {code, _size, bin} ->
        Logger.info("Executing call #{code}")
        result = Calls.call(code, bin)
        Logger.info("Sending response: #{inspect(result)} of size #{byte_size(result)}")
        send_message(stream, result)
        handle_stream(stream)

      {:error, :stream_closed} ->
        Logger.info("Stream closed #{inspect(stream)}")
    end
  end

  def read_code_and_message(stream) do
    Enum.reduce_while(1..100, <<>>, fn _, acc ->
      receive do
        {:quic, :peer_send_shutdown, ^stream, _props} ->
          {:cont, acc}

        {:quic, :send_shutdown_complete, ^stream, _props} ->
          {:cont, acc}

        {:quic, :stream_closed, ^stream, _props} ->
          {:halt, {:error, :stream_closed}}

        {:quic, bin, ^stream, _props} ->
          new_acc = acc <> bin

          if byte_size(new_acc) < 5 do
            {:cont, new_acc}
          else
            <<code::8, m_size::binary-size(4), rest::binary>> = new_acc

            if byte_size(rest) >= de_le(m_size, 4) do
              {:halt, {code, de_le(m_size, 4), rest}}
            else
              {:cont, new_acc}
            end
          end

        x ->
          Logger.error("Unexpected message: #{inspect(x)}")
          {:halt, :unknown_message}
      end
    end)
  end

  def send_message(stream, message) do
    Logger.info("Sending message: #{inspect(message)}")
    :quicer.send(stream, e_le(byte_size(message), 4))
    :quicer.send(stream, message)
  end

  def receive_message(stream) do
    Enum.reduce_while(1..100, <<>>, fn _, acc ->
      receive do
        {:quic, :peer_send_shutdown, ^stream, _props} ->
          {:cont, acc}

        {:quic, :send_shutdown_complete, ^stream, _props} ->
          {:cont, acc}

        {:quic, :stream_closed, ^stream, _props} ->
          {:halt, {:error, :stream_closed}}

        {:quic, bin, ^stream, _props} ->
          new_acc = acc <> bin
          Logger.info("Received message: #{inspect(new_acc)} of size #{byte_size(new_acc)}")

          if byte_size(new_acc) < 4 do
            {:cont, new_acc}
          else
            <<m_size::binary-size(4), rest::binary>> = new_acc

            if byte_size(rest) >= de_le(m_size, 4) do
              {:halt, {:ok, rest}}
            else
              {:cont, new_acc}
            end
          end

        x ->
          Logger.error("Unexpected message: #{inspect(x)}")
          {:halt, {:error, :unknown_message}}
      end
    end)
  end
end
