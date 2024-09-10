defmodule System.HeaderSeal do
  alias System.State.EntropyPool
  alias Block.Header

  # Formula (60) v0.3.4
  # Formula (61)  v0.3.4
  def seal_header(
        %Header{timeslot: ts} = header,
        epoch_slot_sealers,
        %EntropyPool{} = entropy_pool,
        {secret, _}
      ) do
    # associated with formula (60, 61) v0.3.4
    # let i = γs′ [Ht ]↺
    expected_slot_sealer = Enum.at(epoch_slot_sealers, rem(ts, length(epoch_slot_sealers)))
    seal_context = construct_seal_context(expected_slot_sealer, entropy_pool)
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

  # Formula (60) v0.3.4
  # Formula (61)  v0.3.4
  def validate_header_seals(
        header,
        posterior_curr_validators,
        posterior_epoch_slot_sealers,
        %EntropyPool{} = entropy_pool
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
             construct_seal_context(expected_slot_sealer, entropy_pool),
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
         <<_::binary>> = correct_slot_sealer,
         _block_seal_output,
         block_author_key_index,
         posterior_curr_validators
       ) do
    case Enum.at(posterior_curr_validators, block_author_key_index) do
      %{bandersnatch: ^correct_slot_sealer} -> :ok
      _ -> {:error, :ticket_id_mismatch}
    end
  end

  defp verify_sealer_match(%{id: block_seal_output}, block_seal_output, _, _), do: :ok
  defp verify_sealer_match(_, _, _, _), do: {:error, :ticket_id_mismatch}

  def construct_seal_context(<<_::binary>>, %EntropyPool{n3: n3}) do
    SigningContexts.jam_fallback_seal() <> n3
  end

  def construct_seal_context(%{entry_index: i}, %EntropyPool{n3: n3}) do
    SigningContexts.jam_ticket_seal() <> n3 <> <<i::8>>
  end
end
