defmodule System.HeaderSealsVerifier do
  alias System.State.EntropyPool
  alias Block.Header

  def verify_block_seal(
        header,
        ring,
        correct_slot_sealer,
        entropy_pool_history
      ) do
    aux_data =
      if is_fallback_sealer?(correct_slot_sealer) do
        # Formula (61) v0.3.4
        SigningContexts.jam_fallback_seal() <> Enum.at(entropy_pool_history, 2)
      else
        # Formula (60) v0.3.4
        SigningContexts.jam_ticket_seal() <>
          Enum.at(entropy_pool_history, 2) <>
          Map.get(correct_slot_sealer, :entry_index)
      end

    RingVrf.ietf_vrf_verify(
      ring,
      Header.unsigned_serialize(header),
      aux_data,
      header.block_seal,
      header.block_author_key_index
    )
  end

  # Formula (62) v0.3.4
  def verify_vrf_signature(header, ring, output_from_block_seal) do
    RingVrf.ietf_vrf_verify(
      ring,
      <<>>,
      SigningContexts.jam_entropy() <> output_from_block_seal,
      header.vrf_signature,
      header.block_author_key_index
    )
  end

  def validate_both_seals(
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
           verify_block_seal(
             header,
             ring,
             correct_slot_sealer,
             entropy_pool_history
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
           verify_vrf_signature(header, ring, block_seal_output) do
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

  defp is_fallback_sealer?(correct_slot_sealer) do
    case correct_slot_sealer do
      <<_::binary>> -> true
      %{} -> false
      _ -> raise "Unknown sealer type"
    end
  end


end
