defmodule Quic.Flags do
  # Stream Start Flags
  def stream_start_flag(:none), do: 0x0000
  def stream_start_flag(:immediate), do: 0x0001
  def stream_start_flag(:fail_blocked), do: 0x0002
  def stream_start_flag(:shutdown_on_fail), do: 0x0004
  def stream_start_flag(:indicate_peer_accept), do: 0x0008

  # Stream Open Flags
  def stream_open_flag(:none), do: 0x0000
  def stream_open_flag(:unidirectional), do: 0x0001
  def stream_open_flag(:"0_rtt"), do: 0x0002

  # Stream Shutdown Flags
  def stream_shutdown_flag(:none), do: 0x0000
  def stream_shutdown_flag(:graceful), do: 0x0001
  def stream_shutdown_flag(:abort_send), do: 0x0002
  def stream_shutdown_flag(:abort_receive), do: 0x0004
  # abort_send | abort_receive
  def stream_shutdown_flag(:abort), do: 0x0006
  def stream_shutdown_flag(:immediate), do: 0x0008

  # Send Flags
  def send_flag(:none), do: 0x0000
  def send_flag(:"0_rtt"), do: 0x0001
  def send_flag(:start), do: 0x0002
  def send_flag(:fin), do: 0x0004
  def send_flag(:dgram_priority), do: 0x0008
  def send_flag(:delay_send), do: 0x0010
  def send_flag(:sync), do: 0x1000

  # Recieve Flags

  def receive_flag(:none), do: 0x0000
  def receive_flag(:"0_rtt"), do: 0x0001
  def receive_flag(:fin), do: 0x0002
end
