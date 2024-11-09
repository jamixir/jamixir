defmodule Util.TimeTest do
  use ExUnit.Case
  alias Util.Time, as: Time

  test "base time is correct" do
    assert Time.base_time() == :calendar.datetime_to_gregorian_seconds({{2024, 1, 1}, {12, 0, 0}})
  end

  test "current time is after base time" do
    assert Time.current_time() > 0
  end

  test "block time validation for a past block" do
    past_block_time = Time.current_time() - 10
    assert Time.valid_block_time?(past_block_time)
  end

  test "block time validation for a future block" do
    future_block_time = Time.current_time() + 10
    refute Time.valid_block_time?(future_block_time)
  end

  test "block timeslot index validation for a past block" do
    past_block_timeslot = div(Time.current_time() - 10, Constants.slot_period())
    assert Time.valid_block_timeslot?(past_block_timeslot)
  end

  test "block timeslot index validation for a future block" do
    future_block_timeslot = div(Time.current_time() + 10, Constants.slot_period())
    refute Time.valid_block_timeslot?(future_block_timeslot)
  end

  test "new epoch detection when crossing epoch boundary" do
    previous_timeslot = 11
    current_timeslot = 12
    assert Time.new_epoch?(previous_timeslot, current_timeslot)
  end

  test "new epoch detection when within the same epoch" do
    previous_timeslot = 10
    current_timeslot = 11
    assert !Time.new_epoch?(previous_timeslot, current_timeslot)
  end

  test "new epoch detection with large jump across epochs" do
    previous_timeslot = 11
    current_timeslot = 24
    assert Time.new_epoch?(previous_timeslot, current_timeslot)
  end

  test "epoch index calculation" do
    timeslot = 24
    assert Time.epoch_index(timeslot) == 2

    timeslot = 11
    assert Time.epoch_index(timeslot) == 0

    timeslot = 12
    assert Time.epoch_index(timeslot) == 1
  end

  test "epoch phase calculation" do
    timeslot = 12
    assert Time.epoch_phase(timeslot) == 0

    timeslot = 11
    assert Time.epoch_phase(timeslot) == 11

    timeslot = 13
    assert Time.epoch_phase(timeslot) == 1
  end
end
