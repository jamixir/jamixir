defmodule System.Network.Client do
  alias System.Network.Server
  require Logger

  @call_default_config [host: ~c"localhost", port: 9999, timeout: 60_000]

  def start_client(config \\ []) do
    conf = Keyword.merge(@call_default_config, config)

    {:ok, conn} = :quicer.connect(conf[:host], conf[:port], Server.default_opts(), conf[:timeout])

    receive do
      {:quic, :streams_available, c, opts} ->
        Logger.info("Streams available: #{inspect(c)} - #{inspect(opts)}")
    end

    {:ok, stream} = :quicer.start_stream(conn, start_flag: 1)

    :quicer.send(stream, "ping")
    :quicer.shutdown_stream(stream)

    {conn, stream}
  end

  def send_message(config \\ [], do: callback) do
    conf = Keyword.merge(@call_default_config, config)

    {:ok, conn} = :quicer.connect(conf[:host], conf[:port], Server.default_opts(), conf[:timeout])

    receive do
      {:quic, :streams_available, c, opts} ->
        Logger.info("Streams available: #{inspect(c)} - #{inspect(opts)}")
    end

    {:ok, stream} = :quicer.start_stream(conn, start_flag: 1)

    result = callback.(stream)

    result
  end

  @spec ask_block(binary, integer, integer) :: list(Block.t())
  def ask_block(hash, direction \\ 0, max_blocks) do
    message = <<128>> <> hash <> <<direction::8>> <> <<max_blocks::32>>

    send_message([],
      do: fn stream ->
        :quicer.send(stream, message)

        receive do
          {:quic, :dgram_state_changed, _, _} -> nil
        end

        receive do
          {:quic, bin, ^stream, _} ->
            Logger.info("Received #{byte_size(bin)} bytes: #{inspect(bin)}")
            {:ok, Block.decode_list(bin)}

          x ->
            Logger.error("Unexpected message: #{inspect(x)}")
            {:error, :unknown_message}
        after
          10_000 -> {:error, :timeout}
        end
      end
    )
  end
end
