defmodule Network.PeerState do
  defstruct [
    # Listener socket (if started in listen mode)
    :socket,
    # QUIC connection handle
    :connection,
    # Map of stream buffers (stream id -> buffer)
    stream_buffers: %{},
    # Map of stream -> from for pending responses
    pending_responses: %{},
    # Map of UP streams (protocol id -> stream)
    up_streams: %{}
  ]
end
