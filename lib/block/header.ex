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

  def is_valid_header?(_, %Block.Header{parent_hash: nil}), do: true
  def is_valid_header?(storage, header) do
    case storage[header.parent_hash] do
      nil -> false
      parent_header -> 
      parent_header.timeslot_index < header.timeslot_index and 
      is_valid_header?(storage, parent_header)
    end
  end
end