defmodule System.HeaderSeal do
  alias System.State.EntropyPool
  alias Block.Header

  # Formula (60, 61) v0.3.4
  def seal_header(
        %Header{timeslot: ts} = header,
        epoch_slot_sealers,
        %EntropyPool{history: entropy_pool_history},
        {secret, _}
      ) do
    # associated with formula (60, 61) v0.3.4
    # let i = γs′ [Ht ]↺
    expected_slot_sealer = Enum.at(epoch_slot_sealers, rem(ts, length(epoch_slot_sealers)))
    seal_context = construct_seal_context(expected_slot_sealer, entropy_pool_history)
    block_seal_output = RingVrf.ietf_vrf_output(secret, seal_context)

    {vrf_signature, _} =
      RingVrf.ietf_vrf_sign(secret, SigningContexts.jam_entropy() <> block_seal_output, <<>>)

    updated_header = %Header{
      header
      | vrf_signature: vrf_signature
    }

    {block_seal, _} =
      RingVrf.ietf_vrf_sign(secret, seal_context, Header.unsigned_serialize(updated_header))

    %Header{
      updated_header
      | block_seal: block_seal
    }
  end

  # Formula (60, 61) v0.3.4
  def validate_header_seals(
        header,
        posterior_curr_validators,
        posterior_epoch_slot_sealers,
        %EntropyPool{history: entropy_pool_history}
      ) do
    bandersnatch_public_keys = Enum.map(posterior_curr_validators, & &1.bandersnatch)
    # let i = γs′ [Ht ]↺
    expected_slot_sealer =
      posterior_epoch_slot_sealers
      |> Enum.at(rem(header.timeslot, length(posterior_epoch_slot_sealers)))

    # verify that the block seal is a valid signature
    with {:ok, block_seal_output} <-
           RingVrf.ietf_vrf_verify(
             bandersnatch_public_keys,
             construct_seal_context(expected_slot_sealer, entropy_pool_history),
             Header.unsigned_serialize(header),
             header.block_seal,
             header.block_author_key_index
           ),
         # calulate the output ourselves and compare it to the block seal's output
         :ok <-
           verify_sealer_match(
             expected_slot_sealer,
             block_seal_output,
             header.block_author_key_index,
             posterior_curr_validators
           ),
         # verify that the vrf signature is a valid signature
         {:ok, vrf_signature_output} <-
           RingVrf.ietf_vrf_verify(
             bandersnatch_public_keys,
             SigningContexts.jam_entropy() <> block_seal_output,
             <<>>,
             header.vrf_signature,
             header.block_author_key_index
           ) do
      {:ok, %{block_seal_output: block_seal_output, vrf_signature_output: vrf_signature_output}}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp verify_sealer_match(
         correct_slot_sealer,
         block_seal_output,
         block_author_key_index,
         posterior_curr_validators
       ) do
    cond do
      is_fallback_sealer?(correct_slot_sealer) ->
        proposed_slot_sealer =
          Enum.at(posterior_curr_validators, block_author_key_index).bandersnatch

        if proposed_slot_sealer == correct_slot_sealer do
          :ok
        else
          {:error, :ticket_id_mismatch}
        end

      Map.get(correct_slot_sealer, :id) == block_seal_output ->
        :ok

      true ->
        {:error, :ticket_id_mismatch}
    end
  end

  defp is_fallback_sealer?(<<_::binary>>), do: true
  defp is_fallback_sealer?(%{}), do: false

  def construct_seal_context(expected_slot_sealer, entropy_pool_history) do
    if is_fallback_sealer?(expected_slot_sealer) do
      # XF ⌢ η3
      SigningContexts.jam_fallback_seal() <> Enum.at(entropy_pool_history, 2)
    else
      # XT ⌢ η3 ir
      SigningContexts.jam_ticket_seal() <>
        Enum.at(entropy_pool_history, 2) <>
        <<Map.get(expected_slot_sealer, :entry_index)::8>>
    end
  end
end
