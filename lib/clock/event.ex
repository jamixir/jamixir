defmodule Clock.Event do
  alias Util.Time

  # every 6 seconds
  @type event_type ::
          :slot_tick
          # every 8 seconds
          | :audit_tranche
          # every 10 slots
          | :rotate_core_assignments
          # every 30 seconds
          | :assurance_timeout
          | :epoch_transition
          # 1/5 * slot time after epoch transition (impl detail, not a GP constat)
          | :compute_author_slots
          # acoording to the sarfole.slot_sealer list
          | :author_block
          # max(⌊E/60⌋,1) slots after the connectivity changes
          | :produce_new_ticket

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
