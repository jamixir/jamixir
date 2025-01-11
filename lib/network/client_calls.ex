defmodule Network.ClientCalls do
  require Logger

  def log(level, message), do: Logger.log(level, "[QUIC_CLIENT_CALLS] #{message}")

  def call(128, message) do
    log(:info, "Received block response")
    {:ok, Block.decode_list(message)}
  end

  def call(0, _message) do
    log(:info, "Block announcement confirmed")
    :ok
  end

  def call(protocol_id, message) do
    log(:info, "Received protocol #{protocol_id} message")
    {:ok, message}
  end
end
