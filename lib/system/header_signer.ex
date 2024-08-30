defmodule System.HeaderSigner do
  alias System.State.EntropyPool
  alias Block.Header
  alias Util.Safrole

  def sign_block_header(
        header,
        curr_validators,
        epoch_slot_sealers,
        %EntropyPool{history: entropy_pool_history},
        key_pair
      ) do
    {secret, public_key} = key_pair
    author_index = Safrole.find_author_index(curr_validators, public_key)

    ring = Enum.map(curr_validators, & &1.bandersnatch)
    RingVrf.init_ring_context(length(ring))

    correct_slot_sealer =
      Safrole.get_correct_slot_sealer(epoch_slot_sealers, header.timeslot)

    {_, block_seal_output} =
      RingVrf.ring_vrf_sign(
        ring,
        secret,
        author_index,
        Header.unsigned_serialize(header),
        Safrole.construct_sign_context(correct_slot_sealer, entropy_pool_history)
      )

    {_, vrf_output} =
      RingVrf.ring_vrf_sign(
        ring,
        secret,
        author_index,
        <<>>,
        SigningContexts.jam_entropy() <> block_seal_output
      )

    %Header{
      header
      | block_seal: block_seal_output,
        vrf_signature: vrf_output
    }
  end
end
