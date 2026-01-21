defmodule Network.ServerCallsBehaviour do
  @callback call(protocol_id :: integer(), message :: binary() | [binary()], remote_ed25519_key :: binary()) :: term()
end
