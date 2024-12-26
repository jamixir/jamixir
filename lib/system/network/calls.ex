defmodule System.Network.Calls do
  require Logger

  def call(128, bin) do
    <<_hash::32, direction::8, max_blocks::32>> = bin
    Logger.info("Sending #{max_blocks} blocks in direction #{direction}")
    blocks_bins = for _ <- 0..max_blocks, do: File.read!("test/block_mock.bin")
    blocks_bins = if(direction == 0, do: Enum.reverse(blocks_bins), else: blocks_bins)
    Enum.join(blocks_bins)
  end
end
