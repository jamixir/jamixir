defmodule Network.ServerCallsBehaviour do
  @callback call(protocol_id :: integer(), message :: binary() | [binary()]) :: term()
end
