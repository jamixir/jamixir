defmodule Clock.Event do
  alias Util.Time

  @type event_type ::
          :slot_tick #every 6 seconds
          | :slot_phase_tick #every 1 second
          | :audit_tranche #every 8 seconds
          | :rotate_core_assignments #every 10 slots
          | :assurance_timeout #every 30 seconds
          | :epoch_transition
          | :compute_authoring_slots # on the 2nd second of the slot before the epoch transition (impl detail, not a GP constat)
          | :author_block # accoording to the sarfole.slot_sealer list

  @type t :: %__MODULE__{
          event: event_type(),
          local_time: DateTime.t(),
          slot: non_neg_integer(),
          slot_phase: non_neg_integer() | nil,
          epoch: non_neg_integer(),
          epoch_phase: non_neg_integer()
        }

  defstruct [:event, :local_time, :slot, :slot_phase, :epoch, :epoch_phase]

  def new(event_type, timeslot \\ nil, slot_phase \\ nil) do
    current_slot = timeslot || Time.current_timeslot()
    {epoch, epoch_phase} = Time.epoch_index_and_phase(current_slot)

    %__MODULE__{
      event: event_type,
      local_time: DateTime.utc_now(),
      slot: current_slot,
      slot_phase: slot_phase,
      epoch: epoch,
      epoch_phase: epoch_phase
    }
  end
end
