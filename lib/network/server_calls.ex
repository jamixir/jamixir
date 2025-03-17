defmodule Network.ServerCalls do
  alias Block.Extrinsic.TicketProof
  require Logger
  use Codec.Encoder

  def log(message), do: Logger.log(:info, "[QUIC_SERVER_CALLS] #{message}")

  def call(128, <<hash::32, direction::8, max_blocks::32>> = _message) do
    log("Sending #{max_blocks} blocks in direction #{direction}")
    {:ok, blocks} = Jamixir.NodeAPI.get_blocks(hash, direction, max_blocks)
    blocks_bin = for b <- blocks, do: Encodable.encode(b)
    Enum.join(blocks_bin)
  end

  use Sizes

  def call(
        141,
        <<hash::binary-size(@hash_size), bitfield::binary-size(@bitfield_size),
          signature::binary-size(@signature_size)>>
      ) do
    log("Received assurance")
    :ok = Jamixir.NodeAPI.save_assurance(hash, bitfield, signature)
    <<>>
  end

  def call(
        142,
        <<service_id::service(), hash::binary-size(@hash_size), length::32-little>> = _message
      ) do
    log("Receiving Preimage")
    :ok = Jamixir.NodeAPI.receive_preimage(service_id, hash, length)
    <<>>
  end

  def call(143, hash) do
    log("Received preimage request")

    case Jamixir.NodeAPI.get_preimage(hash) do
      {:ok, preimage} -> preimage
      _ -> <<>>
    end
  end

  def call(131, m), do: process_ticket_message(:proxy, m)
  def call(132, m), do: process_ticket_message(:validator, m)

  def call(0, _message) do
    log("Processing block announcement")
    # TODO: Implement block processing
    :ok
  end

  def call(protocol_id, message) do
    Logger.warning(
      "Received unknown message #{protocol_id} on server. Ignoring #{inspect(message)} of size #{byte_size(message)}"
    )

    message
  end

  defp process_ticket_message(
         mode,
         <<epoch::32-little, attempt::8, vrf_proof::binary-size(@bandersnatch_proof_size)>>
       ),
       do: process_ticket(mode, epoch, attempt, vrf_proof)

  defp process_ticket(mode, epoch, attempt, vrf_proof) do
    log("Processing #{mode} ticket")
    ticket = %TicketProof{attempt: attempt, signature: vrf_proof}
    :ok = Jamixir.NodeAPI.process_ticket(mode, epoch, ticket)
    <<>>
  end
end
