defmodule Jamixir.TCPServer do
  def start(port) do
    {:ok, listen_socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])

    IO.puts("Listening on port #{port}...")
    loop_accept(listen_socket)
  end

  defp loop_accept(listen_socket) do
    {:ok, client_socket} = :gen_tcp.accept(listen_socket)
    IO.puts("Client connected")
    spawn_link(Jamixir.TCPServer, :handle_client, [client_socket])
    loop_accept(listen_socket)
  end

  def handle_client(socket) do
    :gen_tcp.send(socket, "Welcome to Jamixir Blockchain Node!\n")
    handle_client_loop(socket)
  end

  defp handle_client_loop(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        IO.puts("Received: #{data}")
        :gen_tcp.send(socket, "Echo: #{data}")
        handle_client_loop(socket)

      {:error, _} ->
        :gen_tcp.close(socket)
        IO.puts("Client disconnected")
    end
  end
end
