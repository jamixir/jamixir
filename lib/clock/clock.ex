defmodule Clock do
  use GenServer
  require Logger
  alias Util.Time


  @slot_phase_duration_ms 1_000
  @assurance_timeout_ms 30_000
  @compute_authoring_slots_phase 2

  # PubSub channel names
  @node_events_channel "node_events"
  @clock_events_channel "clock_events"
  @clock_phase_events_channel "clock_phase_events"

  defp slot_duration_ms, do: Constants.slot_period() * 1000
  defp tranche_duration_ms, do: Constants.audit_trenches_period() * 1000

  defstruct [
    :timers,
    :current_slot,
    :current_slot_phase,
    :authoring_slots
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def set_authoring_slots(authoring_slots) do
    GenServer.cast(__MODULE__, {:set_authoring_slots, authoring_slots})
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
       current_slot_phase: 0,
       authoring_slots: MapSet.new()
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

    new_state = %{
      state
      | current_slot: current_slot,
        timers: Map.put(state.timers, :slot, schedule_slot_timer())
    }

    {:noreply, new_state}
  end

  # Slot phase tick - every second
  def handle_info(:slot_phase_tick, state) do
    current_slot = Time.current_timeslot()
    new_phase = rem(state.current_slot_phase + 1, Constants.slot_period())

    case new_phase do
      @compute_authoring_slots_phase ->
        # Compute authoring slots for next epoch (if needed)
        if should_compute_authoring_slots?(current_slot) do
          compute_event = Clock.Event.new(:compute_authoring_slots, current_slot, new_phase)

          Phoenix.PubSub.broadcast(
            Jamixir.PubSub,
            @clock_phase_events_channel,
            {:clock, compute_event}
          )
        end

      _ ->
        :ok
    end

    new_state = %{
      state
      | current_slot: current_slot,
        current_slot_phase: new_phase,
        timers: Map.put(state.timers, :slot_phase, schedule_slot_phase_timer())
    }

    {:noreply, new_state}
  end

  def handle_info(:audit_tranche, state) do
    event = Clock.Event.new(:audit_tranche)
    Phoenix.PubSub.broadcast(Jamixir.PubSub, @clock_events_channel, {:clock, event})

    new_timers = Map.put(state.timers, :audit, schedule_audit_timer())
    {:noreply, %{state | timers: new_timers}}
  end

  def handle_info(:assurance_timeout, state) do
    event = Clock.Event.new(:assurance_timeout)
    Phoenix.PubSub.broadcast(Jamixir.PubSub, @clock_events_channel, {:clock, event})

    new_timers = Map.put(state.timers, :assurance, schedule_assurance_timer())
    {:noreply, %{state | timers: new_timers}}
  end

  def handle_info(msg, state) do
    Logger.warning("Clock received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp should_compute_authoring_slots?(slot),
    do: Time.epoch_phase(slot) == Constants.epoch_length() - 1

  defp schedule_timer(duration_ms, message), do: Process.send_after(self(), message, duration_ms)

  defp schedule_slot_timer(), do: schedule_timer(slot_duration_ms(), :slot_tick)
  defp schedule_slot_phase_timer(), do: schedule_timer(@slot_phase_duration_ms, :slot_phase_tick)
  defp schedule_audit_timer(), do: schedule_timer(tranche_duration_ms(), :audit_tranche)
  defp schedule_assurance_timer(), do: schedule_timer(@assurance_timeout_ms, :assurance_timeout)
end
