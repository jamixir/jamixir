defmodule System.HeaderSealsVerifier do
  alias System.State.EntropyPool
  alias Block.Header

  def validate_header_seals(
        header,
        posterior_curr_validators,
        posterior_epoch_slot_sealers,
        %EntropyPool{history: entropy_pool_history}
      ) do
    ring = Enum.map(posterior_curr_validators, & &1.bandersnatch)

    # let i = γs′ [Ht ]↺
    correct_slot_sealer =
      posterior_epoch_slot_sealers
      |> Enum.at(rem(header.timeslot, length(posterior_epoch_slot_sealers)))

    with {:ok, block_seal_output} <-
           RingVrf.ietf_vrf_verify(
             ring,
             Util.Safrole.construct_sign_context(correct_slot_sealer, entropy_pool_history),
             Header.unsigned_serialize(header),
             header.block_seal,
             header.block_author_key_index
           ),

         # validate ticket id
         :ok <-
           verify_sealer_match(
             correct_slot_sealer,
             block_seal_output,
             header.block_author_key_index,
             posterior_curr_validators
           ),
         # verify that the vrf signature is also a valid bandersnatch signature
         {:ok, vrf_signature_output} <-
           RingVrf.ietf_vrf_verify(
             ring,
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
      Util.Safrole.is_fallback_sealer?(correct_slot_sealer) ->
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
end
