defmodule System.Network.Rules do
  def preferred_initiator(a, b) when is_binary(a) and is_binary(b) do
    if :binary.at(a, 31) > 127 != :binary.at(b, 31) > 127 != a < b, do: a, else: b
  end
end
