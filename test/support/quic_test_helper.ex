defmodule QuicTestHelper do
  use ExUnit.Case
  alias Network.Peer

  def start_quic_processes(port, peer1_name \\ nil, peer2_name \\ nil) do
    # Start first peer in listening mode
    {:ok, peer1_pid} = Peer.start_link(
      [init_mode: :listener, host: ~c"::1", port: port],
      name: peer1_name
    )
    Process.sleep(50) # Give peer1 time to start listening

    # Start second peer in connecting mode
    {:ok, peer2_pid} = Peer.start_link(
      [init_mode: :initiator, host: ~c"::1", port: port],
      name: peer2_name
    )
    Process.sleep(50) # Give time for connection to establish

    {peer1_pid, peer2_pid}
  end

  def cleanup_processes(peer1_pid, peer2_pid) do
    if Process.alive?(peer1_pid), do: Process.exit(peer1_pid, :kill)
    if Process.alive?(peer2_pid), do: Process.exit(peer2_pid, :kill)
  end
end
