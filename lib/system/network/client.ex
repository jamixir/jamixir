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

    {conn, stream}
  end

  def send_message(code, message, client_config \\ []) do
    {conn, stream} = start_client(client_config)

    receive do
      {:quic, :dgram_state_changed, _, _} -> nil
    end

    :quicer.send(stream, <<code::8>>)
    Server.send_message(stream, message)

    result = Server.receive_message(stream)

    :quicer.shutdown_stream(stream)
    :quicer.close_connection(conn)
    empty_mailbox()
    result
  end

  defp empty_mailbox do
    receive do
      {:quic, _, _, _} -> empty_mailbox()
    after
      0 -> :ok
    end
  end

  def ask_block(hash, direction \\ 0, max_blocks) do
    message = hash <> <<direction::8>> <> <<max_blocks::32>>

    pid = async_operation(fn -> send_message(128, message) end)

    case await_result(pid) do
      {:ok, {:ok, bin}} ->
        blocks = Block.decode_list(bin)
        Logger.info("Received blocks: #{inspect(blocks)}")
        blocks

      {:error, e} ->
        Logger.error("Error: #{inspect(e)}")
        []
    end
  end

  def await_result(pid, timeout \\ 1_000) do
    ref = Process.monitor(pid)

    receive do
      {:result, result} ->
        Process.demonitor(ref, [:flush])
        {:ok, result}

      {:DOWN, ^ref, :process, _pid, :normal} ->
        {:ok, nil}

      {:DOWN, ^ref, :process, _pid, reason} ->
        {:error, reason}
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        {:error, :timeout}
    end
  end

  # Example of spawning process with result
  def async_operation(fun) do
    parent = self()

    spawn(fn ->
      result = fun.()
      send(parent, {:result, result})
    end)
  end
end
