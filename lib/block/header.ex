defmodule Block.Header do
  @type t :: %__MODULE__{
          parent_hash: binary(),
          prior_state_root: binary(),
          extrinsic_hash: binary(),
          timeslot: integer(),
          epoch: integer() | nil,
          winning_tickets_marker: list(binary()) | nil,
          judgements_marker: list(binary()) | nil,
          block_author_key: binary(),
          vrf_signature: binary(),
          block_seal: binary()
        }

  # Equation (37)
  defstruct [
    # Hp
    parent_hash: nil,
    # Hr
    prior_state_root: nil,
    # Hx
    extrinsic_hash: nil,
    # Ht
    timeslot: nil,
    # He
    epoch: nil,
    # Hw
    winning_tickets_marker: nil,
    # Hj
    judgements_marker: nil,
    # Hk
    block_author_key: nil,
    # Hv
    vrf_signature: nil,
    # Hs
    block_seal: nil
  ]

  def is_valid_header?(_, h = %Block.Header{parent_hash: nil}) do
    Util.Time.valid_block_timeslot?(h.timeslot)
  end

  def is_valid_header?(storage, header) do
    case storage[header.parent_hash] do
      nil ->
        false

      parent_header ->
        parent_header.timeslot < header.timeslot and
          Util.Time.valid_block_timeslot?(header.timeslot)
    end
  end
end
