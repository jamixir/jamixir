defmodule System.HeaderSealsVerifier do
  alias System.State.EntropyPool
  alias Block.Header

  def verify_block_seal(
        header,
        ring,
        correct_slot_sealer,
        entropy_pool_history,
        slot_seal_type
      ) do
    aux_data =
      case slot_seal_type do
        :fallback ->
          SigningContexts.jam_fallback_seal() <> Enum.at(entropy_pool_history, 2)

        _ ->
          SigningContexts.jam_ticket_seal() <>
            Enum.at(entropy_pool_history, 2) <>
            Map.get(correct_slot_sealer, :entry_index)
      end

    BandersnatchRingVrf.ietf_vrf_verify(
      ring,
      Header.unsigned_serialize(header),
      aux_data,
      header.block_seal,
      header.block_author_key_index
    )
  end

  def verify_vrf_signature(header, ring, output_from_block_seal) do
    BandersnatchRingVrf.ietf_vrf_verify(
      ring,
      <<>>,
      SigningContexts.jam_entropy() <> output_from_block_seal,
      header.vrf_signature,
      header.block_author_key_index
    )
  end

  def validate_both_seals(
        header,
        state_timeslot,
        posterior_curr_validators,
        posterior_epoch_slot_sealers,
        current_ticket_accumelator,
        %EntropyPool{history: entropy_pool_history}
      ) do
    ring = Enum.map(posterior_curr_validators, & &1.bandersnatch)

    correct_slot_sealer =
      posterior_epoch_slot_sealers
      |> Enum.at(rem(header.timeslot, length(posterior_epoch_slot_sealers)))

    slot_seal_type =
      determine_ticket_or_fallback(header.timeslot, state_timeslot, current_ticket_accumelator)

    with {:ok, block_seal_output} <-
           verify_block_seal(
             header,
             ring,
             correct_slot_sealer,
             entropy_pool_history,
             slot_seal_type
           ),
         :ok <-
           validate_ticket_or_fallback(
             slot_seal_type,
             correct_slot_sealer,
             block_seal_output,
             header.block_author_key_index,
             posterior_curr_validators
           ),
         {:ok, vrf_signature_output} <-
           verify_vrf_signature(header, ring, block_seal_output) do
      {:ok, %{block_seal_output: block_seal_output, vrf_signature_output: vrf_signature_output}}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp validate_ticket_or_fallback(
         :fallback,
         correct_slot_sealer,
         _block_seal_output,
         block_author_key_index,
         posterior_curr_validators
       ) do
    proposed_slot_sealer = Enum.at(posterior_curr_validators, block_author_key_index).bandersnatch
    if proposed_slot_sealer == correct_slot_sealer, do: :ok, else: {:error, :ticket_id_mismatch}
  end

  defp validate_ticket_or_fallback(
         _,
         correct_slot_sealer,
         block_seal_output,
         _block_author_key_index,
         _posterior_curr_validators
       ) do
    if Map.get(correct_slot_sealer, :id) == block_seal_output,
      do: :ok,
      else: {:error, :ticket_id_mismatch}
  end

  def determine_ticket_or_fallback(new_timeslot, timeslot, ticket_accumulator) do
    current_epoch_index = Util.Time.epoch_index(timeslot)
    new_epoch_index = Util.Time.epoch_index(new_timeslot)

    ticket_accumulator_full = length(ticket_accumulator) == Constants.epoch_length()
    ticket_submission_ended = Util.Time.epoch_phase(timeslot) >= Constants.ticket_submission_end()

    cond do
      new_epoch_index == current_epoch_index ->
        :ticket_same

      new_epoch_index == current_epoch_index + 1 and
        ticket_accumulator_full and
          ticket_submission_ended ->
        :ticket_shuffle

      true ->
        :fallback
    end
  end
end
