defmodule Clock.Event do
  alias Util.Time

  @type event_type ::
          :slot_tick | :audit_tranche | :rotation_check | :assurance_timeout | :epoch_transition

  @type t :: %__MODULE__{
          event: event_type(),
          local_time: DateTime.t(),
          slot: non_neg_integer(),
          epoch: non_neg_integer(),
          epoch_phase: non_neg_integer()
        }

  defstruct [:event, :local_time, :slot, :epoch, :epoch_phase]

  def new(event_type, timeslot \\ nil) do
    current_slot = timeslot || Time.current_timeslot()
    {epoch, epoch_phase} = Time.epoch_index_and_phase(current_slot)

    %__MODULE__{
      event: event_type,
      local_time: DateTime.utc_now(),
      slot: current_slot,
      epoch: epoch,
      epoch_phase: epoch_phase
    }
  end
end
