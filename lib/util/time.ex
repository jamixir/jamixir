defmodule Util.Time do
  @epoch :calendar.datetime_to_gregorian_seconds({{2024, 1, 1}, {12, 0, 0}})

  def base_time do
    @epoch
  end

  def current_time do
    :calendar.datetime_to_gregorian_seconds(:calendar.universal_time()) - @epoch
  end

  def valid_block_time?(block_time) do
    block_time <= current_time()
  end
end