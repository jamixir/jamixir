defmodule Jamixir.Genesis do
  import Util.Hex, only: [decode16!: 1]
  import Codec.Encoder
  #Value comes from traces
  #https://github.com/davxy/jam-test-vectors/blob/d039d17f1fa421412128c3c3264a766427e9b927/traces/fallback/00000001.json#L89
  #Could be anything, the important thing is to put genesis state under this key
  @gensis_block_parent "0xb5af8edad70d962097eefa2cef92c8284cf0a7578b70a6b7554cf53ae6d51222"
  def genesis_block_parent, do: h(e(genesis_block_parent_header()))
  def genesis_block_parent_header do
    %Block.Header{
      parent_hash: <<0::hash()>>,
      prior_state_root: <<0::hash()>>,
      extrinsic_hash: <<0::hash()>>,
      timeslot: 0,
      epoch_mark: [

      ],
      winning_tickets_marker: nil,
      offenders_marker: [],
      block_author_key_index: 65_535,
      vrf_signature: <<0::m(bandersnatch_signature)>>,
      block_seal: <<0::m(bandersnatch_signature)>>
    }
  end

end
