defmodule Jamixir.Fuzzer do
  require Logger
  alias Util.Logger, as: Log

  def accept(socket_path) do
    if File.exists?(socket_path), do: File.rm!(socket_path)

    {:ok, sock} =
      :socket.open(:local, :stream, :default)

    :ok = :socket.bind(sock, %{family: :local, path: socket_path})
    :ok = :socket.listen(sock)

    Log.info("Ready to fuzz on #{socket_path}")
    loop_acceptor(sock)
  end

  defp loop_acceptor(listener) do
    case :socket.accept(listener) do
      {:ok, client} ->
        Log.info("New fuzzer client connected")
        Task.start(fn -> handle_client(client) end)
        loop_acceptor(listener)

      {:error, reason} ->
        Log.error("Accept error: #{inspect(reason)}")
    end
  end

  defp handle_client(sock) do
    # simple echo server
    case :socket.recv(sock, 0) do
      {:ok, data} ->
        Log.info("Echoing message: #{inspect(data)}")
        :socket.send(sock, data)
        handle_client(sock)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        Log.error("Recv error: #{inspect(reason)}")
    end
  end
end
