defmodule ServerCallsStub do
  @behaviour Network.ServerCallsBehaviour

  @impl true
  def call(_protocol_id, _message), do: :ok
end
