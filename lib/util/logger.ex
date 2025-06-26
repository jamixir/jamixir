defmodule Util.Logger do
  @moduledoc """
  Centralized logging utility with node identity and consistent formatting.
  Provides different log levels and incorporates node names for multi-node debugging.
  """

  require Logger

  @doc """
  Info level log with node identity
  """
  def info(message, context \\ nil) do
    formatted_message = format_message(message, context)
    Logger.info(formatted_message)
  end

  @doc """
  Debug level log with node identity
  """
  def debug(message, context \\ nil) do
    formatted_message = format_message(message, context)
    Logger.debug(formatted_message)
  end

  @doc """
  Warning level log with node identity
  """
  def warning(message, context \\ nil) do
    formatted_message = format_message(message, context)
    Logger.warning(formatted_message)
  end

  @doc """
  Error level log with node identity
  """
  def error(message, context \\ nil) do
    formatted_message = format_message(message, context)
    Logger.error(formatted_message)
  end

  @doc """
  Connection-specific logging for network events
  Accepts optional connection info (ip/port) for better context
  """
  def connection(level, message, ed25519_key \\ nil, connection_info \\ nil)

  def connection(level, message, ed25519_key, %{ip: ip, port: port})
      when not is_nil(ip) and not is_nil(port) do
    formatted_address = format_ip_port(ip, port)

    context =
      if ed25519_key do
        validator_name = Util.NodeIdentity.get_name_for_key(ed25519_key)
        "[CONN:#{validator_name}@#{formatted_address}]"
      else
        "[CONN@#{formatted_address}]"
      end

    formatted_message = format_message(message, context)
    Logger.log(level, formatted_message)
  end

  def connection(level, message, ed25519_key, _connection_info) do
    context =
      if ed25519_key do
        validator_name = Util.NodeIdentity.get_name_for_key(ed25519_key)
        "[CONN:#{validator_name}]"
      else
        "[CONN]"
      end

    formatted_message = format_message(message, context)
    Logger.log(level, formatted_message)
  end

  # Private helper to format IP addresses properly for IPv4 and IPv6
  defp format_ip_port(ip, port) when tuple_size(ip) == 4 do
    # IPv4: 127.0.0.1:9944
    "#{:inet.ntoa(ip)}:#{port}"
  end

  defp format_ip_port(ip, port) when tuple_size(ip) == 8 do
    # IPv6: [::1]:9944 or [2001:db8::1]:9944
    formatted_ipv6 = :inet.ntoa(ip) |> List.to_string()
    "[#{formatted_ipv6}]:#{port}"
  end

  @doc """
  Validator-specific logging for consensus events
  """
  def consensus(level, message) do
    formatted_message = format_message(message, "[CONSENSUS]")
    Logger.log(level, formatted_message)
  end

  @doc """
  Block-specific logging
  """
  def block(level, message) do
    formatted_message = format_message(message, "[BLOCK]")
    Logger.log(level, formatted_message)
  end

  # Private helper to format messages consistently
  defp format_message(message, context) do
    node_name = Util.NodeIdentity.get_node_name()

    case context do
      nil -> "#{node_name} #{message}"
      context -> "#{node_name}#{context} #{message}"
    end
  end
end
