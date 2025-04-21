defmodule Network.PeerState do
  defstruct [
    # Listener socket (if started in listen mode)
    :socket,
    # QUIC connection handle
    :connection,
    # CLIENT SIDE: Map of stream -> {from, protocol_id} for client-initiated requests
    pending_responses: %{},
    # CLIENT SIDE: Map of UP streams (protocol id -> stream)
    up_streams: %{},

    # SERVER SIDE: Map of stream -> %{protocol_id: id, buffer: binary, complete: boolean}
    server_streams: %{}
  ]
end
