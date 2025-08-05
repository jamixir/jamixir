defmodule Util.Logger do
  @moduledoc """
  Centralized logging utility with node identity and consistent formatting.
  Provides different log levels and incorporates node names for multi-node debugging.
  """

  require Logger
  import Util.Hex, only: [b16: 1]
  alias Network.StreamUtils
  def get_node_name do
    get_node_alias() || "NODE"
  end

  def get_node_alias do
    Application.get_env(:jamixir, :node_alias)
  end
  def log(level, message, context \\ nil) do
    formatted_message = format_message(message, context)
    Logger.log(level, formatted_message)
  end

  def info(message, context \\ nil) do
    formatted_message = format_message(message, context)
    Logger.info(formatted_message)
  end

  def debug(message, context \\ nil) do
    formatted_message = format_message(message, context)
    Logger.debug(formatted_message)
  end

  def warning(message, context \\ nil) do
    formatted_message = format_message(message, context)
    Logger.warning(formatted_message)
  end

  def error(message, context \\ nil) do
    formatted_message = format_message(message, context)
    Logger.error(formatted_message)
  end

  def connection(level, message, ed25519_key, connection_info \\ nil)

  def connection(level, message, ed25519_key, %{ip: ip, port: port}) do
    formatted_address = format_ip_port(ip, port)
    key_prefix = get_key_prefix(ed25519_key)

    context = "[CONN:#{key_prefix}@#{formatted_address}]"
    formatted_message = format_message(message, context)
    Logger.log(level, formatted_message)
  end

  def connection(level, message, ed25519_key, _connection_info) do
    key_prefix = get_key_prefix(ed25519_key)
    context = "[CONN:#{key_prefix}]"
    formatted_message = format_message(message, context)
    Logger.log(level, formatted_message)
  end

  def consensus(level, message) do
    formatted_message = format_message(message, "[CONSENSUS]")
    Logger.log(level, formatted_message)
  end

  def block(level, message) do
    formatted_message = format_message(message, "[BLOCK]")
    Logger.log(level, formatted_message)
  end

  def stream(level, message, stream_ref, protocol_id \\ nil) do
    stream_id = StreamUtils.format_stream_ref(stream_ref)
    protocol_desc = if protocol_id, do: " (#{StreamUtils.protocol_description(protocol_id)})", else: ""
    context = "[STREAM:#{stream_id}#{protocol_desc}]"
    formatted_message = format_message(message, context)
    Logger.log(level, formatted_message)
  end

  # Private helper to format messages consistently
  defp format_message(message, context) do
    node_name = get_node_name()

    case context do
      nil -> "[#{node_name}] #{message}"
      context -> "[#{node_name}]#{context} #{message}"
    end
  end

  defp get_key_prefix(ed25519_key), do: KeyManager.get_known_key(b16(ed25519_key))
  defp format_ip_port(ip, port), do: "#{:inet.ntoa(ip)}:#{port}"

end
