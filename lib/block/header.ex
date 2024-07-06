defmodule Block.Header do
  defstruct [
    parent_hash: nil, #Hp
    prior_state_root: nil, # Hr
    extrinsic_hash: nil, # Hx
    timeslot_index: nil, # Ht
    epoch: nil, # He
    winning_tickets_marker: nil, # Hw
    judgements_marker: nil, # Hj
    block_author_key: nil, # Hk
    vrf_signature: nil, # Hv
    block_seal: nil # Hs
  ]
end