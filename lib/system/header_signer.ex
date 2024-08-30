defmodule System.HeaderSigner do
  alias System.State.EntropyPool
  alias Block.Header
  alias Util.Safrole

  def sign_block_header(
        %Header{} = header,
        curr_validators,
        epoch_slot_sealers,
        %EntropyPool{history: entropy_pool_history},
        key_pair
      ) do
    {secret, public_key} = key_pair

    context =
      Safrole.get_correct_slot_sealer(epoch_slot_sealers, header.timeslot)
      |> Safrole.construct_sign_context(entropy_pool_history)

    {_, block_seal_output} =
      RingVrf.ietf_vrf_sign(
        secret,
        context,
        <<>>
      )

    {vrf_signature, _} =
      RingVrf.ietf_vrf_sign(
        secret,
        SigningContexts.jam_entropy() <> block_seal_output,
        <<>>
      )

    header = %{
      header
      | vrf_signature: vrf_signature,
        block_author_key_index: Safrole.find_author_index(curr_validators, public_key)
    }

    {block_seal, _} =
      RingVrf.ietf_vrf_sign(
        secret,
        context,
        Header.unsigned_serialize(header)
      )

    %{
      header
      | block_seal: block_seal
    }
  end
end
