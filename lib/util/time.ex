defmodule Util.Time do
  @epoch :calendar.datetime_to_gregorian_seconds({{2024, 1, 1}, {12, 0, 0}})
  @block_duration 6
  @epoch_duration 600
  @epoch_duration 600

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
  Returns the epoch duration in blocks.
  """
  def epoch_duration do
    @epoch_duration
  end

  @doc """
  Returns the epoch duration in blocks.
  """
  def epoch_duration do
    @epoch_duration
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

  @doc """
  Determines if a new epoch has started based on the previous and current timeslots.
  """
  def new_epoch?(previous_timeslot, current_timeslot) do
    if previous_timeslot >= current_timeslot do
      {:error,
       "Invalid timeslot order: previous_timeslot (#{previous_timeslot}) is not less than current_timeslot (#{current_timeslot})"}
    else
      previous_epoch = div(previous_timeslot, @epoch_duration)
      current_epoch = div(current_timeslot, @epoch_duration)
      {:ok, current_epoch > previous_epoch}
    end
  end
end
