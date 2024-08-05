ExUnit.start(trace: true)

defmodule TestHelper do
  alias Util.Time, as: Time

  def past_timeslot do
    div(Time.current_time() - 10, Time.block_duration())
  end

  def future_timeslot do
    div(Time.current_time() + 10, Time.block_duration())
  end
end
