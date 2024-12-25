defmodule System.Network.Client do
  require Logger

  def start_client(port \\ 9999) do
    {:ok, conn} =
      :quicer.connect(~c"localhost", port, System.Network.Server.default_opts(), 60_000)

    receive do
      {:quic, :streams_available, c, opts} ->
        Logger.info("Streams available: #{inspect(c)} - #{inspect(opts)}")
    end

    {:ok, stream} = :quicer.start_stream(conn, start_flag: 1)

    :quicer.send(stream, "ping")

    {conn, stream}
  end
end
