defmodule Network.PeerState do
  defstruct [
    # Listener socket (if started in listen mode)
    :socket,
    # QUIC connection handle
    :connection,
    # Map of outgoing streams (we initiated these)
    # {stream -> %{from: pid, buffer: binary}}
    outgoing_streams: %{},
    # Map of UP streams (protocol id -> stream)
    up_streams: %{}
  ]
end
