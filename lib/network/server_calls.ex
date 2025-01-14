defmodule Network.ServerCalls do
  require Logger

  def log(message), do: Logger.log(:info, "[QUIC_SERVER_CALLS] #{message}")

  def call(128, <<hash::32, direction::8, max_blocks::32>> = _message) do
    log("Sending #{max_blocks} blocks in direction #{direction}")
    {:ok, blocks} = Jamixir.NodeAPI.get_blocks(hash, direction, max_blocks)
    blocks_bin = for b <- blocks, do: Encodable.encode(b)
    Enum.join(blocks_bin)
  end

  def call(0, _message) do
    log("Processing block announcement")
    # TODO: Implement block processing
    :ok
  end

  def call(_protocol_id, message), do: message
end
