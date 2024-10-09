defmodule Util.Time do
  @epoch :calendar.datetime_to_gregorian_seconds({{2024, 1, 1}, {12, 0, 0}})

  @doc """
  Returns the base epoch time in Gregorian seconds.
  """
  def base_time do
    @epoch
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

  def validate_block_timeslot(block_timeslot) do
    block_time = block_timeslot * Constants.slot_period()

    # Formula (42) v0.4.0
    if valid_block_time?(block_time) do
      :ok
    else
      {:error, "Invalid block time: block_time (#{block_time}) is in the future"}
    end
  end

  def valid_block_timeslot?(block_timeslot), do: validate_block_timeslot(block_timeslot) == :ok

  def validate_timeslot_order(previous_timeslot, current_timeslot) do
    if previous_timeslot >= current_timeslot do
      {:error,
       "Invalid timeslot order: previous_timeslot (#{previous_timeslot}) is not less than current_timeslot (#{current_timeslot})"}
    else
      :ok
    end
  end

  @doc """
  Determines if a new epoch has started based on the previous and current timeslots.
  """
  def new_epoch?(previous_timeslot, current_timeslot) do
    div(current_timeslot, Constants.epoch_length()) >
      div(previous_timeslot, Constants.epoch_length())
  end

  @doc """
  Determines the epoch index of a given timeslot.
  Formula (47) v0.4.0
  """
  def epoch_index(timeslot), do: div(timeslot, Constants.epoch_length())

  @doc """
  Determines the phase of a given timeslot within an epoch.
  Formula (47) v0.4.0
  """
  def epoch_phase(timeslot), do: rem(timeslot, Constants.epoch_length())

  @doc """
  Returns a tuple containing the epoch index and phase for a given timeslot.
  """
  def epoch_index_and_phase(timeslot), do: {epoch_index(timeslot), epoch_phase(timeslot)}
end
