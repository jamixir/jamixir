defmodule System.State.SafroleState do
  alias System.State.SafroleState

  @moduledoc """
  Represents the Safrole Basic State with components:
  - validator_keys: Next epoch's validators' keys
  - epoch_root: Epoch's root (Bandersnatch ring root)
  - ticket_accumulator: Series of highest-scoring ticket identifiers for the next epoch
  - slot_sealer_series: Current epoch's slot-sealer series
  """

  @type validator_key :: binary()
  @type epoch_root :: binary()
  @type ticket_identifier :: binary()
  @type entry_index :: non_neg_integer()
  @type ticket :: {ticket_identifier(), entry_index()}
  @type ticket_accumulator :: [ticket()]
  # Either a full complement of E tickets or E Bandersnatch keys
  @type slot_sealer :: [binary()]

  @type t :: %SafroleState{
          # γk
          validator_keys: [validator_key()],
          # γz
          epoch_root: epoch_root(),
          # γs
          slot_sealer_series: slot_sealer(),
          # γa
          ticket_accumulator: ticket_accumulator()
        }

  # Equation (47)
  defstruct validator_keys: [],
            epoch_root: <<>>,
            slot_sealer_series: [],
            ticket_accumulator: []
end
