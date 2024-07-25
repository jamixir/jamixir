defmodule Block.Header do

  @type t :: %__MODULE__{
    parent_hash: binary(),
    prior_state_root: binary(),
    extrinsic_hash: binary(),
    timeslot_index: integer(),
    epoch: integer() | nil,
    winning_tickets_marker: list(binary()) | nil,
    judgements_marker: list(binary()) | nil,
    block_author_key: binary(),
    vrf_signature: binary(),
    block_seal: binary()
  }

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
      Util.Time.valid_block_timeslot?(header.timeslot_index)
    end
  end
end
