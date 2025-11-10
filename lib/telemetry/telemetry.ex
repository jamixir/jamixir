defmodule Jamixir.Telemetry do
  @moduledoc """
  Main telemetry module providing simplified API for sending events.
  Automatically handles event ID tracking when needed.
  """

  alias Jamixir.Telemetry.{Client, Events}

  @doc """
  Send a telemetry event. Non-blocking.
  """
  def send_event(event) when is_binary(event) do
    <<_::64, event_id::8, _::binary>> = event
    Util.Logger.debug("Sending telemetry event with ID #{event_id}")
    Client.send_event(event)
  end

  def status(status) do
    Events.status(status) |> send_event()
  end

  ## Convenience functions for common events

  def best_block_changed(slot, header_hash) do
    Events.best_block_changed(slot, header_hash) |> send_event()
  end

  def sync_status_changed(in_sync) do
    Events.sync_status_changed(in_sync) |> send_event()
  end

  # Networking events

  def connecting_out(peer_id, peer_address) do
    event = Events.connecting_out(peer_id, peer_address)
    event_id = Client.get_event_id()
    send_event(event)
    event_id
  end

  def connected_out(event_id) do
    Events.connected_out(event_id) |> send_event()
  end

  def connect_out_failed(event_id, reason) do
    Events.connect_out_failed(event_id, reason) |> send_event()
  end

  def connecting_in(peer_address) do
    event = Events.connecting_in(peer_address)
    event_id = Client.get_event_id()
    send_event(event)
    event_id
  end

  def connected_in(event_id, peer_id) do
    Events.connected_in(event_id, peer_id) |> send_event()
  end

  def connect_in_failed(event_id, reason) do
    Events.connect_in_failed(event_id, reason) |> send_event()
  end

  def disconnected(peer_id, terminator, reason) do
    Events.disconnected(peer_id, terminator, reason) |> send_event()
  end

  def peer_misbehaved(peer_id, reason) do
    Events.peer_misbehaved(peer_id, reason) |> send_event()
  end

  # Block authoring/importing events

  def authoring(slot, parent_hash) do
    event = Events.authoring(slot, parent_hash)
    event_id = Client.get_event_id()
    send_event(event)
    event_id
  end

  def authored(event_id, block) do
    block_outline = Events.encode_block_outline(block)
    Events.authored(event_id, block_outline) |> send_event()
  end

  def authoring_failed(event_id, reason) do
    Events.authoring_failed(event_id, reason) |> send_event()
  end

  def importing(slot, block) do
    block_outline = Events.encode_block_outline(block)
    event = Events.importing(slot, block_outline)
    event_id = Client.get_event_id()
    send_event(event)
    event_id
  end

  def block_executed(event_id, accumulated_services \\ []) do
    Events.block_executed(event_id, accumulated_services) |> send_event()
  end

  # Block distribution events

  def block_announced(peer_id, side, slot, header_hash) do
    Events.block_announced(peer_id, side, slot, header_hash) |> send_event()
  end

  # Safrole ticket events

  def generating_tickets(epoch_index) do
    event = Events.generating_tickets(epoch_index)
    event_id = Client.get_event_id()
    send_event(event)
    event_id
  end

  def tickets_generated(event_id, ticket_outputs) do
    Events.tickets_generated(event_id, ticket_outputs) |> send_event()
  end

  def ticket_transferred(peer_id, sender_side, is_validator, epoch_index, attempt, vrf_output) do
    Events.ticket_transferred(
      peer_id,
      sender_side,
      is_validator,
      epoch_index,
      attempt,
      vrf_output
    )
    |> send_event()
  end

  # Guarantee events

  def receiving_guarantee(peer_id) do
    event = Events.receiving_guarantee(peer_id)
    event_id = Client.get_event_id()
    send_event(event)
    event_id
  end

  def guarantee_received(event_id, guarantee_outline) do
    Events.guarantee_received(event_id, guarantee_outline) |> send_event()
  end

  def guarantee_receive_failed(event_id, reason) do
    Events.guarantee_receive_failed(event_id, reason) |> send_event()
  end
end
