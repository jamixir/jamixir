defmodule Network.Calls do
  require Logger

  def call(128, bin) do
    <<hash::32, direction::8, max_blocks::32>> = bin
    Logger.info("Sending #{max_blocks} blocks in direction #{direction}")

    {:ok, blocks} = Jamixir.NodeAPI.get_blocks(hash, direction, max_blocks)

    blocks_bin = for b <- blocks, do: Encodable.encode(b)
    Enum.join(blocks_bin)
  end
end
