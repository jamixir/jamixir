defmodule Jamixir.Genesis do
  import Codec.Encoder
  #Value comes from traces
  #https://github.com/davxy/jam-test-vectors/blob/d039d17f1fa421412128c3c3264a766427e9b927/traces/fallback/00000001.json#L89
  #Could be anything, the important thing is to put genesis state under this key
  def genesis_header_hash, do: h(e(genesis_block_header()))
  def genesis_block_header do
    JsonReader.read(header_file()) |> Block.Header.from_json()
  end

  def default_file do
    Path.join(:code.priv_dir(:jamixir), "genesis.json")
  end

  def header_file do
    Path.join(:code.priv_dir(:jamixir), "genesis_header.json")
  end
end
