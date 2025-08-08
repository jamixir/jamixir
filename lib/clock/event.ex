defmodule Clock.Event do
  alias Util.Time

  @type event_type ::
          :slot_tick | :slot_phase_tick | :audit_tranche | :rotation_check | :assurance_timeout | :epoch_transition | :compute_authoring_slots

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
