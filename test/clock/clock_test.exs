defmodule ClockTest do
  alias Util.Time
  use ExUnit.Case, async: false

  @node_events "node_events"
  @clock_events "clock_events"

  setup_all do
    {:ok, state} = Clock.init([])
    {:ok, state: state}
  end

  test "audit tranche timer broadcasts audit events", %{state: state} do
    Phoenix.PubSub.subscribe(Jamixir.PubSub, @clock_events)
    {:noreply, new_state} = Clock.handle_info(:audit_tranche, state)
    assert new_state.timers[:audit] != state.timers[:audit]
    assert_receive {:clock, %Clock.Event{event: :audit_tranche}}, 100
  end

  test "assurance timeout broadcasts timeout events", %{state: state} do
    Phoenix.PubSub.subscribe(Jamixir.PubSub, @clock_events)
    {:noreply, new_state} = Clock.handle_info(:assurance_timeout, state)
    assert new_state.timers[:assurance] != state.timers[:assurance]
    assert_receive {:clock, %Clock.Event{event: :assurance_timeout}}, 100
  end

  test "compute_author_slots broadcasts to node events", %{state: state} do
    Phoenix.PubSub.subscribe(Jamixir.PubSub, @node_events)
    {:noreply, new_state} = Clock.handle_info(:compute_author_slots, state)

    assert state == new_state
    assert_receive {:clock, event}, 100

    assert event.event == :compute_author_slots
    assert event.slot == state.current_slot
    assert event.epoch == Time.epoch_index(state.current_slot)
    assert event.epoch_phase == Time.epoch_phase(state.current_slot)
  end

  test "produce_new_tickets broadcasts to node events", %{state: state} do
    Phoenix.PubSub.subscribe(Jamixir.PubSub, @node_events)
    {:noreply, new_state} = Clock.handle_info({:produce_new_tickets, 5}, state)
    assert state == new_state
    assert_receive {:clock, %Clock.Event{event: {:produce_new_tickets, 5}}}
  end

  describe "set_authoring_slots/2" do
    test "set_authoring_slots updates state", %{state: state} do
      state = %{state | authoring_slots: MapSet.new()}
      current_slot = Util.Time.current_timeslot()
      epoch = Util.Time.epoch_index(current_slot)
      new_slots = MapSet.new([{epoch, 1}, {epoch, 3}, {epoch, 5}])

      {:noreply, new_state} = Clock.handle_cast({:set_authoring_slots, new_slots}, state)
      assert new_state.authoring_slots == new_slots
    end

    test "set_authoring_slots cleans old epoch data", %{state: state} do
      current_slot = Util.Time.current_timeslot()
      epoch = Util.Time.epoch_index(current_slot)
      state = %{state | authoring_slots: MapSet.new([{epoch - 1, 2}, {epoch, 4}])}
      {:noreply, new_state} = Clock.handle_cast({:set_authoring_slots, MapSet.new([])}, state)
      assert new_state.authoring_slots == MapSet.new([{epoch, 4}])
    end

    test "set_authoring_slots keeps current epoch data", %{state: state} do
      current_slot = Util.Time.current_timeslot()
      epoch = Util.Time.epoch_index(current_slot)
      state = %{state | authoring_slots: MapSet.new([{epoch, 2}])}

      {:noreply, new_state} =
        Clock.handle_cast({:set_authoring_slots, MapSet.new([{epoch + 1, 1}])}, state)

      assert new_state.authoring_slots == MapSet.new([{epoch, 2}, {epoch + 1, 1}])
    end
  end
end
