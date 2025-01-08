defmodule QuicLogFilter do
  def filter(%{msg: {:string, msg}}, _opts) do
    if String.contains?(msg, "QUIC_CLIENT") do
      # Let these messages through
      :ignore
    else
      # Stop all other messages
      :stop
    end
  end

  def filter(_log_event, _opts), do: :ignore
end
