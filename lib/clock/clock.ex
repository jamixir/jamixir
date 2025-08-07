defmodule Clock do
  use GenServer
  require Logger
  alias Util.Time

  defp slot_duration_ms, do: Constants.slot_period() * 1000
  defp tranche_duration_ms, do: Constants.audit_trenches_period() * 1000
  # 30 seconds assurance timeout
  defp assurance_timeout_ms, do: 30_000

  defstruct [
    :timers
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do

    timers = %{
      slot: schedule_slot_timer(),
      audit: schedule_audit_timer(),
      assurance: schedule_assurance_timer()
    }

    {:ok,
     %__MODULE__{
       timers: timers
     }}
  end

  def handle_info(:slot_tick, state) do
    current_slot = Time.current_timeslot()


    event = Clock.Event.new(:slot_tick, current_slot)
    Phoenix.PubSub.broadcast(Jamixir.PubSub, "clock_events", {:clock_event, event})

    if Time.rotation?(current_slot) do
      rotation_event = Clock.Event.new(:rotation_check, current_slot)
      Phoenix.PubSub.broadcast(Jamixir.PubSub, "clock_events", {:clock_event, rotation_event})
    end

    if Time.epoch_transition?(current_slot) do
      epoch_event = Clock.Event.new(:epoch_transition, current_slot)
      Phoenix.PubSub.broadcast(Jamixir.PubSub, "clock_events", {:clock_event, epoch_event})
    end

    new_timers = Map.put(state.timers, :slot, schedule_slot_timer())
    {:noreply, %{state | timers: new_timers}}
  end

  def handle_info(:audit_tranche, state) do
    event = Clock.Event.new(:audit_tranche)
    Phoenix.PubSub.broadcast(Jamixir.PubSub, "clock_events", {:clock_event, event})

    new_timers = Map.put(state.timers, :audit, schedule_audit_timer())
    {:noreply, %{state | timers: new_timers}}
  end

  def handle_info(:assurance_timeout, state) do
    event = Clock.Event.new(:assurance_timeout)
    Phoenix.PubSub.broadcast(Jamixir.PubSub, "clock_events", {:clock_event, event})

    new_timers = Map.put(state.timers, :assurance, schedule_assurance_timer())
    {:noreply, %{state | timers: new_timers}}
  end

  def handle_info(msg, state) do
    Logger.warning("ClockWall received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp schedule_timer(duration_ms, message) do
    Process.send_after(self(), message, duration_ms)
  end

  defp schedule_slot_timer(), do: schedule_timer(slot_duration_ms(), :slot_tick)
  defp schedule_audit_timer(), do: schedule_timer(tranche_duration_ms(), :audit_tranche)
  defp schedule_assurance_timer(), do: schedule_timer(assurance_timeout_ms(), :assurance_timeout)
end
