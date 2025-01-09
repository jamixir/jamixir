defmodule QuicTestHelper do
  use ExUnit.Case
  def start_quic_processes(port, server_name, client_name) do
    {:ok, server_pid} = Quic.Server.start_link(port, name: server_name)
    {:ok, client_pid} = Quic.Client.start_link([port: port], name: client_name)
    Process.sleep(100)

    on_exit(fn ->
      try do
        if pid = Process.whereis(server_name), do: GenServer.stop(pid)
      catch
        _kind, _reason -> :ok
      end

      try do
        if pid = Process.whereis(client_name), do: GenServer.stop(pid)
      catch
        _kind, _reason -> :ok
      end
    end)

    {server_pid, client_pid}
  end
end
