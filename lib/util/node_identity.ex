defmodule Util.NodeIdentity do
  @moduledoc """
  Maps ed25519 keys to friendly names for easier identification.
  """
  import Util.Hex, only: [b16: 1]

  # Map ed25519 keys to validator names (matching genesis.json ordering)
  @key_to_name %{
    # ALICE
    "0x3b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da29" => "ALICE",
    # BOB
    "0x22351e22105a19aabb42589162ad7f1ea0df1c25cebf0e4a9fcd261301274862" => "BOB",
    # CHARLIE
    "0xe68e0cf7f26c59f963b5846202d2327cc8bc0c4eff8cb9abd4012f9a71decf00" => "CHARLIE",
    # DAVE
    "0xb3e0e096b02e2ec98a3441410aeddd78c95e27a0da6f411a09c631c0f2bea6e9" => "DAVE",
    # EVE
    "0x5c7f34a4bd4f2d04076a8c6f9060a0c8d2c6bdd082ceb3eda7df381cb260faff" => "EVE",
    # FERGIE
    "0x837ce344bc9defceb0d7de7e9e9925096768b7adb4dad932e532eb6551e0ea02" => "FERGIE"
  }

  @doc """
  Gets the node name based on our ed25519 key.
  Returns a formatted string like "[ALICE]" for easy log identification.
  """
  def get_node_name do
    case get_name_from_our_key() do
      nil -> "[NODE]"
      name -> "[#{name}]"
    end
  end

  @doc """
  Gets the raw node name without brackets
  """
  def get_raw_node_name do
    get_name_from_our_key() || "NODE"
  end

  @doc """
  Gets the node name for a given ed25519 key
  """
  def get_name_for_key(ed25519_key) when is_binary(ed25519_key) do
    hex_key = if byte_size(ed25519_key) == 32 do
      b16(ed25519_key)
    else
      ed25519_key
    end

    Map.get(@key_to_name, hex_key, "NODE_#{String.slice(hex_key, 0, 8)}")
  end


  # Private functions

  defp get_name_from_our_key do
    case KeyManager.get_our_ed25519_key() do
      nil -> nil
      key -> get_name_for_key(key)
    end
  end
end
