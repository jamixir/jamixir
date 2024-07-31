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
    past_block_timeslot = div(Time.current_time() - 10, Time.block_duration())
    assert Time.valid_block_timeslot?(past_block_timeslot)
  end

  test "block timeslot index validation for a future block" do
    future_block_timeslot = div(Time.current_time() + 10, Time.block_duration())
    refute Time.valid_block_timeslot?(future_block_timeslot)
  end

  test "new epoch detection when crossing epoch boundary" do
    previous_timeslot = 599
    current_timeslot = 600
    assert Time.new_epoch?(previous_timeslot, current_timeslot) == {:ok, true}
  end

  test "new epoch detection when within the same epoch" do
    previous_timeslot = 100
    current_timeslot = 200
    assert Time.new_epoch?(previous_timeslot, current_timeslot) == {:ok, false}
  end

  test "new epoch detection with large jump across epochs" do
    previous_timeslot = 599
    current_timeslot = 1200
    assert Time.new_epoch?(previous_timeslot, current_timeslot) == {:ok, true}
  end

  test "new epoch detection when previous_timeslot is greater than current_timeslot" do
    previous_timeslot = 600
    current_timeslot = 599

    assert {:error, _error_msg} = Time.new_epoch?(previous_timeslot, current_timeslot)
  end
end
