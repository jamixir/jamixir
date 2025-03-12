defmodule Network.ServerCalls do
  require Logger

  def log(message), do: Logger.log(:info, "[QUIC_SERVER_CALLS] #{message}")

  def call(128, <<hash::32, direction::8, max_blocks::32>> = _message) do
    log("Sending #{max_blocks} blocks in direction #{direction}")
    {:ok, blocks} = Jamixir.NodeAPI.get_blocks(hash, direction, max_blocks)
    blocks_bin = for b <- blocks, do: Encodable.encode(b)
    Enum.join(blocks_bin)
  end

  def call(142, <<service_id::32-little, hash::binary-size(32), length::32-little>> = _message) do
    log("Announcing preimage")
    :ok = Jamixir.NodeAPI.announce_preimage(service_id, hash, length)
    <<>>
  end

  def call(143, hash) do
    log("Requesting preimage")

    case Jamixir.NodeAPI.get_preimage(hash) do
      {:ok, preimage} -> preimage
      _ -> <<>>
    end
  end

  def call(0, _message) do
    log("Processing block announcement")
    # TODO: Implement block processing
    :ok
  end

  def call(protocol_id, message) do
    Logger.warning(
      "Received unknown message #{protocol_id} on server. Ignoring #{inspect(message)}"
    )

    message
  end
end
