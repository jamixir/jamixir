defmodule Jamixir.Telemetry.Events do
  @moduledoc """
  Telemetry event builders according to JIP-3 specification.
  Each event includes a timestamp and discriminator.
  Uses existing Codec.Encoder for JAM-compliant encoding.
  """

  alias Codec.NilDiscriminator
  import Codec.Encoder

  # Event discriminators
  @event_dropped 0
  @event_status 10
  @event_best_block_changed 11
  @event_finalized_block_changed 12
  @event_sync_status_changed 13

  # Networking events
  @event_connection_refused 20
  @event_connecting_in 21
  @event_connect_in_failed 22
  @event_connected_in 23
  @event_connecting_out 24
  @event_connect_out_failed 25
  @event_connected_out 26
  @event_disconnected 27
  @event_peer_misbehaved 28

  # Block authoring/importing events
  @event_authoring 40
  @event_authoring_failed 41
  @event_authored 42
  @event_importing 43
  @event_block_verification_failed 44
  @event_block_verified 45
  @event_block_execution_failed 46
  @event_block_executed 47

  # Block distribution events
  @event_block_announcement_stream_opened 60
  @event_block_announcement_stream_closed 61
  @event_block_announced 62

  # Safrole ticket events
  @event_generating_tickets 80
  @event_ticket_generation_failed 81
  @event_tickets_generated 82
  @event_ticket_transfer_failed 83
  @event_ticket_transferred 84

  # Guarantee events
  @event_receiving_guarantee 110
  @event_guarantee_receive_failed 111
  @event_guarantee_received 112

  ## Status Events

  @doc """
  Event 10: Status - Emitted periodically (~2s) with node state summary
  """
  def status(status) do
    status_bin = <<
      status.peer_count::32-little,
      status.validator_count::32-little,
      status.announcement_streams_count::32-little,
      e(status.guarantees_in_pool)::binary,
      status.shards_count::32-little,
      status.shards_total_size::64-little,
      status.preimages_count::32-little,
      status.preimages_total_size::32-little
    >>

    e({timestamp(), @event_status, status_bin})
  end

  @doc """
  Event 11: Best block changed
  """
  def best_block_changed(slot, header_hash) do
    e({timestamp(), @event_best_block_changed, slot, header_hash})
  end

  @doc """
  Event 12: Finalized block changed
  """
  def finalized_block_changed(slot, header_hash) do
    e({timestamp(), @event_finalized_block_changed, slot, header_hash})
  end

  @doc """
  Event 13: Sync status changed
  """
  def sync_status_changed(in_sync) do
    sync_byte = if in_sync, do: 1, else: 0
    e({timestamp(), @event_sync_status_changed, sync_byte})
  end

  ## Networking Events

  @doc """
  Event 20: Connection refused
  """
  def connection_refused(peer_address) do
    e({timestamp(), @event_connection_refused, encode_peer_address(peer_address)})
  end

  @doc """
  Event 21: Connecting in (inbound connection accepted)
  """
  def connecting_in(peer_address) do
    e({timestamp(), @event_connecting_in, encode_peer_address(peer_address)})
  end

  @doc """
  Event 22: Connect in failed
  """
  def connect_in_failed(event_id, reason) do
    e({timestamp(), @event_connect_in_failed, <<event_id::64-little>>, vs(reason)})
  end

  @doc """
  Event 23: Connected in
  """
  def connected_in(event_id, peer_id) do
    e({timestamp(), @event_connected_in, <<event_id::64-little>>, peer_id})
  end

  @doc """
  Event 24: Connecting out (outbound connection initiated)
  """
  def connecting_out(peer_id, peer_address) do
    e({timestamp(), @event_connecting_out, peer_id, encode_peer_address(peer_address)})
  end

  @doc """
  Event 25: Connect out failed
  """
  def connect_out_failed(event_id, reason) do
    e({timestamp(), @event_connect_out_failed, <<event_id::64-little>>, vs(reason)})
  end

  @doc """
  Event 26: Connected out
  """
  def connected_out(event_id) do
    e({timestamp(), @event_connected_out, <<event_id::64-little>>})
  end

  @doc """
  Event 27: Disconnected
  """
  def disconnected(peer_id, terminator, reason) do
    terminator = NilDiscriminator.new(encode_connection_side_value(terminator))

    e({timestamp(), @event_disconnected, peer_id, terminator, vs(reason)})
  end

  @doc """
  Event 28: Peer misbehaved
  """
  def peer_misbehaved(peer_id, reason) do
    e({timestamp(), @event_peer_misbehaved, peer_id, vs(reason)})
  end

  ## Block Authoring/Importing Events

  @doc """
  Event 40: Authoring (block authoring begins)
  """
  def authoring(slot, parent_hash) do
    e({timestamp(), @event_authoring, slot, parent_hash})
  end

  @doc """
  Event 41: Authoring failed
  """
  def authoring_failed(event_id, reason) do
    e({timestamp(), @event_authoring_failed, <<event_id::64-little>>, vs(reason)})
  end

  @doc """
  Event 42: Authored (block authored successfully)
  """
  def authored(event_id, block_outline) do
    e({timestamp(), @event_authored, <<event_id::64-little>>, block_outline})
  end

  @doc """
  Event 43: Importing (block import begins)
  """
  def importing(slot, block_outline) do
    e({timestamp(), @event_importing, slot, block_outline})
  end

  @doc """
  Event 47: Block executed
  """
  def block_executed(event_id, accumulated_services) do
    services_encoded = e(Codec.VariableSize.new(accumulated_services))

    e({timestamp(), @event_block_executed, <<event_id::64-little>>, services_encoded})
  end

  ## Block Distribution Events

  @doc """
  Event 60: Block announcement stream opened
  """
  def block_announcement_stream_opened(peer_id, side) do
    side_byte = encode_connection_side_value(side)

    e({timestamp(), @event_block_announcement_stream_opened, peer_id, side_byte})
  end

  @doc """
  Event 62: Block announced
  """
  def block_announced(peer_id, side, slot, header_hash) do
    side_byte = encode_connection_side_value(side)

    e({timestamp(), @event_block_announced, peer_id, side_byte, slot, header_hash})
  end

  ## Safrole Ticket Events

  @doc """
  Event 80: Generating tickets
  """
  def generating_tickets(epoch_index) do
    e({timestamp(), @event_generating_tickets, <<epoch_index::32-little>>})
  end

  @doc """
  Event 82: Tickets generated
  """
  def tickets_generated(event_id, ticket_outputs) do
    outputs_encoded = e(vs(ticket_outputs))

    e({timestamp(), @event_tickets_generated, <<event_id::64-little>>, outputs_encoded})
  end

  @doc """
  Event 83: Ticket transfer failed
  """
  def ticket_transfer_failed(peer_id, sender_side, is_validator, reason) do
    side_byte = encode_connection_side_value(sender_side)
    is_validator_byte = if is_validator, do: 1, else: 0

    e(
      {timestamp(), @event_ticket_transfer_failed, peer_id, side_byte, is_validator_byte,
       vs(reason)}
    )
  end

  @doc """
  Event 84: Ticket transferred
  """
  def ticket_transferred(peer_id, sender_side, is_validator, epoch_index, attempt, vrf_output) do
    side_byte = encode_connection_side_value(sender_side)
    is_validator_byte = if is_validator, do: 1, else: 0

    e(
      {timestamp(), @event_ticket_transferred, peer_id, side_byte, is_validator_byte, epoch_index,
       attempt, vrf_output}
    )
  end

  ## Guarantee Events

  @doc """
  Event 110: Receiving guarantee
  """
  def receiving_guarantee(peer_id) do
    e({timestamp(), @event_receiving_guarantee, peer_id})
  end

  @doc """
  Event 111: Guarantee receive failed
  """
  def guarantee_receive_failed(event_id, reason) do
    e({timestamp(), @event_guarantee_receive_failed, <<event_id::64-little>>, vs(reason)})
  end

  @doc """
  Event 112: Guarantee received
  """
  def guarantee_received(event_id, guarantee_outline) do
    e({timestamp(), @event_guarantee_received, <<event_id::64-little>>, guarantee_outline})
  end

  ## Helper Functions

  defp encode_peer_address({ip, port}) when is_tuple(ip) do
    # Convert IPv4/IPv6 to 16-byte IPv6 address + 2-byte port
    ipv6_bytes =
      case tuple_size(ip) do
        4 ->
          # IPv4 - map to IPv6 (::ffff:x.x.x.x)
          {a, b, c, d} = ip
          <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF, a, b, c, d>>

        8 ->
          # IPv6
          {a, b, c, d, e, f, g, h} = ip
          <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>
      end

    ipv6_bytes <> <<port::16>>
  end

  defp encode_peer_address(_), do: <<0::128, 0::16>>

  defp encode_connection_side_value(:local), do: 0
  defp encode_connection_side_value(:remote), do: 1
  defp encode_connection_side_value(_), do: nil

  @doc """
  Encode a block outline for telemetry
  """
  def encode_block_outline(block) do
    header_hash = h(e(block.header))

    # Return a tuple that can be encoded
    <<
      byte_size(e(block))::32-little,
      header_hash::binary,
      length(block.extrinsic.tickets)::32-little,
      length(block.extrinsic.preimages)::32-little,
      total_preimage_size(block.extrinsic.preimages)::32-little,
      length(block.extrinsic.guarantees)::32-little,
      length(block.extrinsic.assurances)::32-little,
      length(block.extrinsic.disputes.verdicts)::32-little
    >>
  end

  defp total_preimage_size(preimages) do
    for p <- preimages, reduce: 0 do
      acc -> acc + byte_size(p.blob)
    end
  end

  defp timestamp do
    time = Util.Time.current_time() * 1_000_000
    <<time::64-little>>
  end
end
