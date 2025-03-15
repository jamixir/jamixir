defmodule Network.ServerCalls do
  require Logger

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
        <<hash::@hash_size*8, bitfield::@bitfield_size*8, signature::@signature_size*8>>
      ) do
    log("Received assurance")
    :ok = Jamixir.NodeAPI.save_assurance(hash, bitfield, signature)
    <<>>
  end

  def call(142, <<service_id::32-little, hash::binary-size(32), length::32-little>> = _message) do
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

  def call(131, <<attempt::8, vrf_proof::binary-size(@bandersnatch_proof_size)>>),
    do: process_ticket(:proxy, attempt, vrf_proof)

  def call(132, <<attempt::8, vrf_proof::binary-size(@bandersnatch_proof_size)>>),
    do: process_ticket(:validator, attempt, vrf_proof)

  defp process_ticket(mode, attempt, vrf_proof) do
    log("Processing #{mode} ticket")
    :ok = Jamixir.NodeAPI.process_ticket(mode, attempt, vrf_proof)
    <<>>
  end

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
end
