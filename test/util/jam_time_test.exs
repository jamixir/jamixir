defmodule JamTimeTest do
  use ExUnit.Case

  test "base time is correct" do
    assert JamTime.base_time() == :calendar.datetime_to_gregorian_seconds({{2024, 1, 1}, {12, 0, 0}})
  end

  test "current time is after base time" do
    assert JamTime.current_time() > 0
  end

  test "block time validation for a past block" do
    past_block_time = JamTime.current_time() - 10
    assert JamTime.valid_block_time?(past_block_time)
  end

  test "block time validation for a future block" do
    future_block_time = JamTime.current_time() + 10
    refute JamTime.valid_block_time?(future_block_time)
  end
end