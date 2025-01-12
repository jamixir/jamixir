defmodule Network.PeerState do
  defstruct [
    # Listener socket (if started in listen mode)
    :socket,
    # QUIC connection handle
    :connection,
    # Map of outgoing streams (we initiated these)
    outgoing_streams: %{},
    # Map of UP streams (tracked for block announcements)
    up_streams: %{}
  ]
end
