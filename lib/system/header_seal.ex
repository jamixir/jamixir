defmodule System.HeaderSeal do
  alias System.State.EntropyPool
  alias Block.Header

  def seal_header(
        %Header{timeslot: ts} = header,
        epoch_slot_sealers,
        %EntropyPool{history: entropy_pool_history},
        {secret, _}
      ) do
    selected_slot_sealer = Enum.at(epoch_slot_sealers, rem(ts, length(epoch_slot_sealers)))
    seal_context = construct_sign_context(selected_slot_sealer, entropy_pool_history)
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

  def validate_header_seals(
        header,
        posterior_curr_validators,
        posterior_epoch_slot_sealers,
        %EntropyPool{history: entropy_pool_history}
      ) do
    ring = Enum.map(posterior_curr_validators, & &1.bandersnatch)

    correct_slot_sealer =
      posterior_epoch_slot_sealers
      |> Enum.at(rem(header.timeslot, length(posterior_epoch_slot_sealers)))

    with {:ok, block_seal_output} <-
           RingVrf.ietf_vrf_verify(
             ring,
             construct_sign_context(correct_slot_sealer, entropy_pool_history),
             Header.unsigned_serialize(header),
             header.block_seal,
             header.block_author_key_index
           ),
         :ok <-
           verify_sealer_match(
             correct_slot_sealer,
             block_seal_output,
             header.block_author_key_index,
             posterior_curr_validators
           ),
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

  defp verify_sealer_match(%{id: sealer_id}, block_seal_output, _, _)
       when sealer_id == block_seal_output,
       do: :ok

  defp verify_sealer_match(_, _, _, _), do: {:error, :ticket_id_mismatch}

  defp is_fallback_sealer?(<<_::binary>>), do: true
  defp is_fallback_sealer?(%{}), do: false

  # # Function to construct signing context based on the correct slot sealer and entropy pool history
  def construct_sign_context(correct_slot_sealer, entropy_pool_history) do
    if is_fallback_sealer?(correct_slot_sealer) do
      SigningContexts.jam_fallback_seal() <> Enum.at(entropy_pool_history, 2)
    else
      SigningContexts.jam_ticket_seal() <>
        Enum.at(entropy_pool_history, 2) <>
        <<Map.get(correct_slot_sealer, :entry_index)::8>>
    end
  end
end
