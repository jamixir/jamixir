defmodule QuicTestHelper do
  use ExUnit.Case

  def start_quic_processes(port, server_name \\ nil, client_name \\ nil) do
    {:ok, server_pid} = Quic.Server.start_link(port, name: server_name)
    {:ok, client_pid} = Quic.Client.start_link([port: port], name: client_name)
    Process.sleep(100)
    {server_pid, client_pid}
  end

  def cleanup_processes(server_pid, client_pid) do
    if Process.alive?(server_pid), do: Process.exit(server_pid, :kill)
    if Process.alive?(client_pid), do: Process.exit(client_pid, :kill)
  end
end
