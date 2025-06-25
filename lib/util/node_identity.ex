defmodule Util.NodeIdentity do
  @moduledoc """
  Maps ports to friendly names for easier identification.
  """

  # Map ports to validator names (matching genesis.json ordering)
  @port_to_name %{
    10001 => "ALICE",
    10002 => "BOB",
    10003 => "CHARLIE",
    10004 => "DAVE",
    10005 => "EVE",
    10006 => "FERGIE"
  }

  @doc """
  Gets the node name based on current port.
  Returns a formatted string like "[ALICE]" for easy log identification.
  """
  def get_node_name do
    case get_name_from_port() do
      nil -> "[NODE]"
      name -> "[#{name}]"
    end
  end

  @doc """
  Gets the raw node name without brackets
  """
  def get_raw_node_name do
    get_name_from_port() || "NODE"
  end

  @doc """
  Gets the node name for a given port
  """
  def get_name_for_port(port) do
    Map.get(@port_to_name, port, "NODE#{port}")
  end

  @doc """
  Gets a short address representation with node name
  """
  def format_address(address) when is_binary(address) do
    # Extract port from address like "0000:0000:0000:0000:0000:0000:0000:0001:10001"
    case String.split(address, ":") |> List.last() do
      port_str when is_binary(port_str) ->
        case Integer.parse(port_str) do
          {port, ""} -> get_name_for_port(port)
          _ -> "#{String.slice(address, -8, 8)}"
        end

      _ ->
        "#{String.slice(address, -8, 8)}"
    end
  end

  # Private functions

  defp get_name_from_port do
    port = Application.get_env(:jamixir, :port)
    if port, do: Map.get(@port_to_name, port), else: nil
  end
end
