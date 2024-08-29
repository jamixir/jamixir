defmodule System.HeaderSealsVerifier do
  alias System.State.EntropyPool
  alias Block.Header

  def verify_block_seal(
        header,
        state_timeslot,
        ring,
        posterior_epoch_slot_sealers,
        entropy_pool_history
      ) do
    vrf_input_data = Header.unsigned_serialize(header)
    tau_3 = Enum.at(entropy_pool_history, 2)

    aux_data =
      case determine_ticket_or_fallback(
             header.timeslot,
             state_timeslot,
             posterior_epoch_slot_sealers
           ) do
        :fallback ->
          "$jam_fallback_seal" <> tau_3

        result when result in [:ticket_same, :ticket_shuffle] ->
          if(result == :ticket_same, do: "$jam_ticket_seal", else: "$jam_ticket_shuffle") <>
            tau_3 <>
            (posterior_epoch_slot_sealers
             |> Enum.at(rem(header.timeslot, length(posterior_epoch_slot_sealers)))
             |> Map.get(:entry_index))
      end

    BandersnatchRingVrf.ietf_vrf_verify(
      ring,
      vrf_input_data,
      aux_data,
      header.block_seal,
      header.block_author_key_index
    )
  end

  def verify_vrf_signature(header, ring, output_from_block_seal) do
    BandersnatchRingVrf.ietf_vrf_verify(
      ring,
      <<>>,
      "$jam_entropy" <> output_from_block_seal,
      header.vrf_signature,
      header.block_author_key_index
    )
  end

  def validate_both_seals(
        header,
        state_timeslot,
        posterior_curr_validators,
        posterior_epoch_slot_sealers,
        %EntropyPool{history: entrpy_pool_history}
      ) do
    ring = Enum.map(posterior_curr_validators, & &1.bandersnatch)

    with {:ok, block_seal_output} <-
           verify_block_seal(
             header,
             state_timeslot,
             ring,
             posterior_epoch_slot_sealers,
             entrpy_pool_history
           ),
         {:ok, vrf_signature_output} <-
           verify_vrf_signature(header, ring, block_seal_output) do
      {:ok,
       %{
         block_seal_output: block_seal_output,
         vrf_signature_output: vrf_signature_output
       }}
    else
      {:error, reason} -> {:error, reason}
    end
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
