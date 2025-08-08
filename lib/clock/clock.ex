defmodule Clock do
  use GenServer
  require Logger
  alias Util.Time

  defp slot_duration_ms, do: Constants.slot_period() * 1000
  defp slot_phase_duration_ms, do: 1000  # 1 second per phase
  defp tranche_duration_ms, do: Constants.audit_trenches_period() * 1000
  # 30 seconds assurance timeout
  defp assurance_timeout_ms, do: 30_000

  defstruct [
    :timers,
    :current_slot,
    :current_slot_phase
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    current_slot = Time.current_timeslot()

    timers = %{
      slot: schedule_slot_timer(),
      slot_phase: schedule_slot_phase_timer(),
      audit: schedule_audit_timer(),
      assurance: schedule_assurance_timer()
    }

    {:ok,
     %__MODULE__{
       timers: timers,
       current_slot: current_slot,
       current_slot_phase: 0
     }}
  end

  # Regular slot tick - once per slot, existing behavior
  def handle_info(:slot_tick, state) do
    current_slot = Time.current_timeslot()

    event = Clock.Event.new(:slot_tick, current_slot)
    Phoenix.PubSub.broadcast(Jamixir.PubSub, "clock_events", {:clock, event})

    if Time.rotation?(current_slot) do
      rotation_event = Clock.Event.new(:rotation_check, current_slot)
      Phoenix.PubSub.broadcast(Jamixir.PubSub, "clock_events", {:clock, rotation_event})
    end

    if Time.epoch_transition?(current_slot) do
      epoch_event = Clock.Event.new(:epoch_transition, current_slot)
      Phoenix.PubSub.broadcast(Jamixir.PubSub, "clock_events", {:clock, epoch_event})
    end

    new_timers = Map.put(state.timers, :slot, schedule_slot_timer())
    {:noreply, %{state | timers: new_timers}}
  end

  # Slot phase tick - every second within a slot
  def handle_info(:slot_phase_tick, state) do
    current_slot = Time.current_timeslot()

    # Check if we've moved to a new slot
    {new_slot, new_phase} =
      if current_slot != state.current_slot do
        # New slot started, reset to phase 0
        {current_slot, 0}
      else
        # Same slot, increment phase
        next_phase = rem(state.current_slot_phase + 1, 6)
        {state.current_slot, next_phase}
      end

    # Send slot_phase_tick event on separate channel
    phase_event = Clock.Event.new(:slot_phase_tick, new_slot, new_phase)
    Phoenix.PubSub.broadcast(Jamixir.PubSub, "clock_phase_events", {:clock, phase_event})

    # Handle special phase events
    case new_phase do
      2 ->
        # Phase 2: Compute authoring slots for next epoch (if needed)
        if should_compute_authoring_slots?(new_slot) do
          compute_event = Clock.Event.new(:compute_authoring_slots, new_slot, new_phase)
          Phoenix.PubSub.broadcast(Jamixir.PubSub, "clock_phase_events", {:clock, compute_event})
        end

      _ ->
        # Other phases: do nothing for now
        :ok
    end

    new_state = %{state |
      current_slot: new_slot,
      current_slot_phase: new_phase,
      timers: Map.put(state.timers, :slot_phase, schedule_slot_phase_timer())
    }

    {:noreply, new_state}
  end

  def handle_info(:audit_tranche, state) do
    event = Clock.Event.new(:audit_tranche)
    Phoenix.PubSub.broadcast(Jamixir.PubSub, "clock_events", {:clock, event})

    new_timers = Map.put(state.timers, :audit, schedule_audit_timer())
    {:noreply, %{state | timers: new_timers}}
  end

  def handle_info(:assurance_timeout, state) do
    event = Clock.Event.new(:assurance_timeout)
    Phoenix.PubSub.broadcast(Jamixir.PubSub, "clock_events", {:clock, event})

    new_timers = Map.put(state.timers, :assurance, schedule_assurance_timer())
    {:noreply, %{state | timers: new_timers}}
  end

  def handle_info(msg, state) do
    Logger.warning("Clock received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Determine if we should compute authoring slots
  # This happens at epoch phase 11 (last slot) at slot phase 2 (2 seconds into the slot)
  defp should_compute_authoring_slots?(slot) do
    epoch_phase = Time.epoch_phase(slot)
    # Compute authoring slots when we're in the last slot of an epoch (phase 11)
    epoch_phase == Constants.epoch_length() - 1
  end

  defp schedule_timer(duration_ms, message) do
    Process.send_after(self(), message, duration_ms)
  end

  defp schedule_slot_timer(), do: schedule_timer(slot_duration_ms(), :slot_tick)
  defp schedule_slot_phase_timer(), do: schedule_timer(slot_phase_duration_ms(), :slot_phase_tick)
  defp schedule_audit_timer(), do: schedule_timer(tranche_duration_ms(), :audit_tranche)
  defp schedule_assurance_timer(), do: schedule_timer(assurance_timeout_ms(), :assurance_timeout)
end
