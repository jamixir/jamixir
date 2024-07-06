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
end