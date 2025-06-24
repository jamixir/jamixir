defmodule Network.PeerState do
  defstruct [
    # Listener socket (when started in listen mode)
    :socket,
    # QUIC connection handle
    :connection,
    # Remote peer information
    :remote_address,
    :remote_port,
    # Local port information
    :local_port,
    # Flag to track if connection closure has been handled
    connection_closed: false,
    # Map of stream -> {from, protocol_id, buffer}
    # Used by clients to track streams expecting responses
    pending_responses: %{},
    # Map of protocol_id -> stream
    # Client: Determines if a new up stream should be created or an existing one reused
    # Server: Used by UpStreamManager to manage stream lifecycle
    up_streams: %{},
    # Map of stream -> %{protocol_id: id, buffer: binary}
    # Used by server to track data received on up streams
    up_stream_data: %{},
    # Map of stream -> %{protocol_id: id, buffer: binary, complete: boolean}
    # Used to track data received on sp streams
    ce_streams: %{}
  ]
end
