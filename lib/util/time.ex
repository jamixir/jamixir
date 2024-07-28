defmodule Util.Time do
  @epoch :calendar.datetime_to_gregorian_seconds({{2024, 1, 1}, {12, 0, 0}})
  @block_duration 6

  @doc """
  Returns the base epoch time in Gregorian seconds.
  """
  def base_time do
    @epoch
  end

  @doc """
  Returns the block duration in seconds.
  """
  def block_duration do
    @block_duration
  end

  @doc """
  Returns seconds passed since epoch time.
  """
  def current_time do
    :calendar.datetime_to_gregorian_seconds(:calendar.universal_time()) - @epoch
  end

  @doc """
  Checks if the given block time is valid (i.e., not in the future).
  """
  def valid_block_time?(block_time) do
    block_time <= current_time()
  end

  @doc """
  Checks if the given block timeslot index is valid by multiplying it by the block duration and comparing to the current time.
  """

  def valid_block_timeslot?(block_timeslot) do
    block_time = block_timeslot * @block_duration
    valid_block_time?(block_time)
  end
end
