defmodule Jamixir.TimeTicker do
  use GenServer
  require Logger
  alias Util.Time

  @default_tick_interval 500

  # Client API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subscribe do
    GenServer.call(__MODULE__, :subscribe)
  end

  # Server callbacks
  @impl true
  def init(opts) do
    tick_interval = Keyword.get(opts, :tick_interval, @default_tick_interval)

    state = %{
      tick_interval: tick_interval,
      last_timeslot: Time.current_timeslot(),
      subscribers: []
    }

    schedule_tick(tick_interval)
    {:ok, state}
  end

  @impl true
  def handle_call(:subscribe, {pid, _ref}, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: [pid | state.subscribers]}}
  end

  @impl true
  def handle_info(:tick, state) do
    new_timeslot = Time.current_timeslot()

    if new_timeslot != state.last_timeslot do
      Logger.info("🕒 Time has come: #{new_timeslot}")
      broadcast_timeslot(new_timeslot, state.subscribers)
    end

    schedule_tick(state.tick_interval)
    {:noreply, %{state | last_timeslot: new_timeslot}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: List.delete(state.subscribers, pid)}}
  end

  # Private functions
  defp schedule_tick(interval) do
    Process.send_after(self(), :tick, interval)
  end

  defp broadcast_timeslot(timeslot, subscribers) do
    message = {:new_timeslot, timeslot}
    Enum.each(subscribers, &send(&1, message))
  end
end
