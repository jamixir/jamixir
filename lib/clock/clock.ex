defmodule Clock do
  use GenServer
  require Logger
  alias Util.Time
  use MapUnion

  # PubSub channel names
  @node_events_channel "node_events"
  @clock_events_channel "clock_events"

  defp slot_duration_ms, do: Constants.slot_period() * 1000
  defp tranche_duration_ms, do: Constants.audit_trenches_period() * 1000
  # assurances distribution happen after 2/3 of slot passed (4s for 6s slot period)
  defp assurance_timeout_ms, do: div(4 * slot_duration_ms(), 6)

  defstruct [:timers, :current_slot, :authoring_slots, :reference_time]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def set_authoring_slots(authoring_slots) do
    GenServer.cast(__MODULE__, {:set_authoring_slots, authoring_slots})
  end

  def init(opts) do
    initial_slot = Time.current_timeslot()

    current_slot =
      if opts[:no_wait] do
        initial_slot
      else
        Stream.repeatedly(&Time.current_timeslot/0) |> Enum.find(&(&1 != initial_slot))
      end

    # sleeps 3 ms to ensure we're well within the new slot
    Process.sleep(3)

    # We're at the beginning of current_slot, so use current time as reference
    reference_time = System.monotonic_time(:millisecond)

    Logger.debug(
      "Clock initialized at slot #{current_slot} with reference time #{reference_time}"
    )

    timers = %{
      slot: schedule_timer(reference_time, 0, :slot_tick),
      audit: schedule_timer(reference_time, 0, :audit_tranche),
      assurance: schedule_timer(reference_time, 0, :assurance_timeout)
    }

    # Schedule compute_author_slots for current epoch 2 seconds after the next tick
    # Only if we have at least 2 slots remaining in the epoch
    epoch_phase = Time.epoch_phase(current_slot)

    if epoch_phase <= Constants.epoch_length() - 3 do
      schedule_timer(
        reference_time,
        slot_duration_ms() + div(slot_duration_ms(), 3),
        :compute_current_epoch_author_slots
      )
    end

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
    current_slot = Time.current_timeslot()

    # keep only future authoring slots
    new_assigned_slots =
      for {epoch, phase} <- state.authoring_slots ++ authoring_slots,
          epoch >= Time.epoch_index(current_slot),
          into: MapSet.new(),
          do: {epoch, phase}

    {:noreply, %{state | authoring_slots: new_assigned_slots}}
  end

  def handle_info(:slot_tick, state) do
    current_slot = Time.current_timeslot()
    epoch = Time.epoch_index(current_slot)
    epoch_phase = Time.epoch_phase(current_slot)

    Logger.info("⏰ Slot tick: slot=#{current_slot}, epoch=#{epoch}, phase=#{epoch_phase}")
    Phoenix.PubSub.broadcast(Jamixir.PubSub, @node_events_channel, {:clock, :telemetry_status})
    Phoenix.PubSub.broadcast(Jamixir.PubSub, @node_events_channel, {:clock, :sync_status})

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
      # Ticket sent to proxy should be performed max(⌊E/60⌋, 1)
      # slots after the connectivity changes for a new epoch are applied
      schedule_timer(
        state.reference_time,
        max(div(Constants.epoch_length(), 60), 1) * slot_duration_ms(),
        {:produce_new_tickets, epoch + 1}
      )

      epoch_event = Clock.Event.new(:epoch_transition, current_slot)
      Phoenix.PubSub.broadcast(Jamixir.PubSub, @clock_events_channel, {:clock, epoch_event})
    end

    if epoch_phase == Constants.epoch_length() - 1 do
      schedule_timer(state.reference_time, div(slot_duration_ms(), 3), :compute_author_slots)
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

  def handle_info({:produce_new_tickets, target_epoch}, state),
    do: default_handle_info({:produce_new_tickets, target_epoch}, state)

  def handle_info(:compute_author_slots, state),
    do: default_handle_info(:compute_author_slots, state)

  def handle_info(:compute_current_epoch_author_slots, state) do
    current_slot = Time.current_timeslot()
    compute_event = Clock.Event.new(:compute_current_epoch_author_slots, current_slot)
    Phoenix.PubSub.broadcast(Jamixir.PubSub, @node_events_channel, {:clock, compute_event})
    {:noreply, state}
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
    Phoenix.PubSub.broadcast(Jamixir.PubSub, @node_events_channel, {:clock, event})

    next_assurance_time = state.reference_time + assurance_timeout_ms()

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

  defp default_handle_info(type, state) do
    compute_event = Clock.Event.new(type, state.current_slot)
    Phoenix.PubSub.broadcast(Jamixir.PubSub, @node_events_channel, {:clock, compute_event})
    {:noreply, state}
  end

  defp schedule_timer(reference_time, offset_ms, message) do
    now = System.monotonic_time(:millisecond)
    target_time = reference_time + offset_ms
    delay = max(0, target_time - now)
    Process.send_after(self(), message, delay)
  end
end
