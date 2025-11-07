defmodule Jamixir.Telemetry.EventsTest do
  use ExUnit.Case
  import Jamixir.Telemetry.Events
  import Jamixir.Factory

  test "check constants correct values" do
    block = build(:block)
    assert is_binary(encode_block_outline(block))
  end
end
