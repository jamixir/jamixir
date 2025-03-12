defmodule Network.ClientCalls do
  require Logger

  def log(message), do: Logger.log(:info, "[QUIC_CLIENT_CALLS] #{message}")

  def call(128, message) do
    log("Received block response")
    {:ok, Block.decode_list(message)}
  end

  def call(142, _message) do
    log("Preimage announcement confirmed.")
    :ok
  end

  def call(143, message) do
    log("Preimage request confirmed.")

    case message do
      <<>> -> {:error, :not_found}
      _ -> {:ok, message}
    end
  end

  def call(0, _message) do
    log("Block announcement confirmed")
    :ok
  end

  def call(protocol_id, message) do
    log("Received protocol #{protocol_id} message")
    {:ok, message}
  end
end
