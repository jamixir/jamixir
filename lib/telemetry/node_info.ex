defmodule Jamixir.Telemetry.NodeInfo do
  @moduledoc """
  Builds the node information message (first message sent to telemetry server).
  """

  alias Jamixir.Genesis
  alias Jamixir.Meta
  alias PVM.Host.General.Internal
  import Codec.Encoder

  @protocol_version 0

  def build do
    # Return a tuple that can be encoded by Codec.Encoder
    {
      # Protocol version (u8)
      @protocol_version,
      # JAM Parameters (from PVM fetch host call) - NOT variable-length encoded, raw binary
      Internal.encode_jam_parameters(),
      # Genesis header hash (32 bytes) - raw binary, no length prefix
      Genesis.genesis_header_hash(),
      # Peer ID (our Ed25519 public key - 32 bytes) - raw binary, no length prefix
      KeyManager.get_our_ed25519_key(),
      # Peer Address (18 bytes: 16 bytes IPv6 + 2 bytes port) - raw binary, no length prefix
      encode_peer_address(),
      # Node flags (u32) - will be encoded as 4 bytes
      node_flags(),
      # Node implementation name (variable-length string)
      vs(Meta.name()),
      # Node implementation version (variable-length string)
      vs(format_app_version()),
      # Gray Paper version (variable-length string)
      vs(format_jam_version()),
      # Additional note (variable-length string)
      vs("Elixir JAM implementation")
    }
  end

  defp encode_peer_address do
    # Get the listening port from config
    port = Application.get_env(:jamixir, :port, 9999)

    # IPv6 address (::1 for localhost, or :: for all interfaces) + port
    # 16 bytes IPv6 + 2 bytes port (big-endian)
    ipv6 = <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
    ipv6 <> <<port::16-big>>
  end

  defp node_flags do
    <<0, 0, 0, 0>>
  end

  defp format_app_version do
    {major, minor, patch} = Meta.app_version()
    "#{major}.#{minor}.#{patch}"
  end

  defp format_jam_version do
    {major, minor, patch} = Meta.jam_version()
    "#{major}.#{minor}.#{patch}"
  end
end
