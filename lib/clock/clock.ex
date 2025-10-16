defmodule Clock do
  use GenServer
  require Logger
  alias Util.Time

  @assurance_timeout_ms 30_000
  @compute_authoring_slots_phase 2

  # PubSub channel names
  @node_events_channel "node_events"
  @clock_events_channel "clock_events"
  @clock_phase_events_channel "clock_phase_events"

  defp slot_duration_ms, do: Constants.slot_period() * 1000
  defp tranche_duration_ms, do: Constants.audit_trenches_period() * 1000

  defstruct [:timers, :current_slot, :authoring_slots, :reference_time]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def set_authoring_slots(authoring_slots) do
    GenServer.cast(__MODULE__, {:set_authoring_slots, authoring_slots})
  end

  def init(_opts) do
    current_slot = Time.current_timeslot()
    now = System.monotonic_time(:millisecond)

    # Calculate the next slot boundary as our reference time
    slot_duration = slot_duration_ms()
    time_since_slot_start = rem(now, slot_duration)
    reference_time = now + (slot_duration - time_since_slot_start)

    timers = %{
      slot: schedule_timer(reference_time, 0, :slot_tick),
      audit: schedule_timer(reference_time, 0, :audit_tranche),
      assurance: schedule_timer(reference_time, 0, :assurance_timeout)
    }

    {:ok,
     %__MODULE__{
       timers: timers,
       current_slot: current_slot,
       authoring_slots: MapSet.new(),
       reference_time: reference_time
     }}
  end

  def handle_cast({:set_authoring_slots, authoring_slots}, state) do
    Logger.info("⏰ Clock received authoring slots: #{inspect(authoring_slots)}")
    {:noreply, %{state | authoring_slots: authoring_slots}}
  end

  def handle_info(:slot_tick, state) do
    current_slot = Time.current_timeslot()
    epoch = Time.epoch_index(current_slot)
    epoch_phase = Time.epoch_phase(current_slot)

    Logger.debug("⏰ Slot tick: slot=#{current_slot}, epoch=#{epoch}, phase=#{epoch_phase}")

    # Check if this is an authoring slot and send author_block event
    if MapSet.member?(state.authoring_slots, {epoch, epoch_phase}) do
      author_event = Clock.Event.new(:author_block, current_slot)
      Phoenix.PubSub.broadcast(Jamixir.PubSub, @node_events_channel, {:clock, author_event})
    end

    if Time.rotation?(current_slot) do
      rotation_event = Clock.Event.new(:rotate_core_assignments, current_slot)
      Phoenix.PubSub.broadcast(Jamixir.PubSub, @clock_events_channel, {:clock, rotation_event})
    end

    if Time.epoch_transition?(current_slot) do
      epoch_event = Clock.Event.new(:epoch_transition, current_slot)
      Phoenix.PubSub.broadcast(Jamixir.PubSub, @clock_events_channel, {:clock, epoch_event})
    end

    if epoch_phase == @compute_authoring_slots_phase do
      # Compute authoring slots for next epoch (if needed)
      if should_compute_authoring_slots?(current_slot) do
        compute_event = Clock.Event.new(:compute_authoring_slots, current_slot, epoch_phase)

        Phoenix.PubSub.broadcast(
          Jamixir.PubSub,
          @clock_phase_events_channel,
          {:clock, compute_event}
        )
      end
    end

    next_slot_offset = slot_duration_ms()
    new_reference_time = state.reference_time + next_slot_offset

    new_state = %{
      state
      | current_slot: current_slot,
        reference_time: new_reference_time,
        timers: Map.put(state.timers, :slot, schedule_timer(new_reference_time, 0, :slot_tick))
    }

    {:noreply, new_state}
  end

  def handle_info(:audit_tranche, state) do
    event = Clock.Event.new(:audit_tranche)
    Phoenix.PubSub.broadcast(Jamixir.PubSub, @clock_events_channel, {:clock, event})
    next_audit_time = state.reference_time + tranche_duration_ms()
    new_timers = Map.put(state.timers, :audit, schedule_timer(next_audit_time, 0, :audit_tranche))

    {:noreply, %{state | timers: new_timers}}
  end

  def handle_info(:assurance_timeout, state) do
    event = Clock.Event.new(:assurance_timeout)
    Phoenix.PubSub.broadcast(Jamixir.PubSub, @clock_events_channel, {:clock, event})
    next_assurance_time = state.reference_time + @assurance_timeout_ms

    new_timers =
      Map.put(
        state.timers,
        :assurance,
        schedule_timer(next_assurance_time, 0, :assurance_timeout)
      )

    {:noreply, %{state | timers: new_timers}}
  end

  def handle_info(msg, state) do
    Logger.warning("Clock received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp should_compute_authoring_slots?(slot),
    do: Time.epoch_phase(slot) == Constants.epoch_length() - 1

  defp schedule_timer(reference_time, offset_ms, message) do
    now = System.monotonic_time(:millisecond)
    target_time = reference_time + offset_ms
    delay = max(0, target_time - now)
    Process.send_after(self(), message, delay)
  end
end
