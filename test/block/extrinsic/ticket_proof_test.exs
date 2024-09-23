defmodule Block.Extrinsic.TicketProofTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block.Extrinsic.TicketProof

  defp create_valid_tickets(count, state, key_pairs) do
    ring = Enum.map(state.curr_validators, & &1.bandersnatch)

    Enum.map(0..(count - 1), fn i ->
      {secret, _} = Enum.at(key_pairs, rem(i, length(key_pairs)))
      entry_index = rem(i, 2)

      {proof, _} =
        RingVrf.ring_vrf_sign(
          ring,
          secret,
          i,
          SigningContexts.jam_ticket_seal() <> state.entropy_pool.n2 <> <<entry_index>>,
          <<>>
        )

      %TicketProof{entry_index: entry_index, ticket_validity_proof: proof}
    end)
  end

  defp create_valid_proof(state, {secret, _}, prover_idx, entry_index) do
    RingVrf.ring_vrf_sign(
      Enum.map(state.curr_validators, & &1.bandersnatch),
      secret,
      prover_idx,
      SigningContexts.jam_ticket_seal() <> state.entropy_pool.n2 <> <<entry_index>>,
      <<>>
    )
  end

  defp create_and_sort_tickets(count, state, key_pairs) do
    create_valid_tickets(count, state, key_pairs)
    |> Enum.map(fn %TicketProof{entry_index: r, ticket_validity_proof: proof} ->
      {:ok, output_hash} =
        RingVrf.ring_vrf_verify(
          state.safrole.epoch_root,
          SigningContexts.jam_ticket_seal() <> state.entropy_pool.n2 <> <<r>>,
          <<>>,
          proof
        )

      {output_hash, %TicketProof{entry_index: r, ticket_validity_proof: proof}}
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  setup_all do
    build(:genesis_state_with_safrole)
  end

  describe "validate_tickets/5 - passing cases" do
    test "succeeds with single ticket before submission end", %{
      state: state,
      key_pairs: key_pairs
    } do
      {proof, _} = create_valid_proof(state, List.first(key_pairs), 0, 0)

      assert :ok ==
               TicketProof.validate_tickets(
                 [%TicketProof{entry_index: 0, ticket_validity_proof: proof}],
                 Constants.ticket_submission_end() - 1,
                 Constants.ticket_submission_end() - 2,
                 state.entropy_pool,
                 state.safrole
               )
    end

    test "succeeds with multiple tickets before submission end", %{
      state: state,
      key_pairs: key_pairs
    } do
      tickets = create_and_sort_tickets(2, state, key_pairs)

      assert :ok ==
               TicketProof.validate_tickets(
                 tickets,
                 Constants.ticket_submission_end() - 1,
                 Constants.ticket_submission_end() - 2,
                 state.entropy_pool,
                 state.safrole
               )
    end

    test "succeeds with empty tickets after submission end", %{state: state} do
      assert :ok ==
               TicketProof.validate_tickets(
                 [],
                 Constants.ticket_submission_end(),
                 Constants.ticket_submission_end() - 1,
                 state.entropy_pool,
                 state.safrole
               )
    end
  end

  describe "validate_tickets/5 - failing cases" do
    test "fails with too many tickets", %{state: state} do
      assert {:error, "Invalid number of tickets for the current epoch phase"} =
               TicketProof.validate_tickets(
                 List.duplicate(%TicketProof{}, Constants.max_tickets() + 1),
                 Constants.ticket_submission_end() - 1,
                 Constants.ticket_submission_end() - 2,
                 state.entropy_pool,
                 state.safrole
               )
    end

    test "fails with invalid entry index", %{state: state} do
      assert {:error, "Invalid entry index"} =
               TicketProof.validate_tickets(
                 [%TicketProof{entry_index: 2, ticket_validity_proof: <<1, 2, 3>>}],
                 499,
                 400,
                 state.entropy_pool,
                 state.safrole
               )
    end

    test "fails with invalid signature", %{state: state, key_pairs: key_pairs} do
      {valid_proof, _} = create_valid_proof(state, List.first(key_pairs), 0, 0)
      <<first_byte, rest::binary>> = valid_proof
      invalid_proof = <<first_byte + 1>> <> rest

      assert {:error, "Invalid ticket validity proof"} =
               TicketProof.validate_tickets(
                 [%TicketProof{entry_index: 0, ticket_validity_proof: invalid_proof}],
                 1,
                 0,
                 state.entropy_pool,
                 state.safrole
               )
    end

    test "fails with non-unique tickets", %{state: state, key_pairs: key_pairs} do
      ticket = create_valid_tickets(1, state, key_pairs) |> List.first()

      assert {:error, :duplicates} ==
               TicketProof.validate_tickets(
                 [ticket, ticket],
                 Constants.ticket_submission_end() - 1,
                 Constants.ticket_submission_end() - 2,
                 state.entropy_pool,
                 state.safrole
               )
    end

    test "fails when ticket proof is in gamma_a", %{state: state, key_pairs: key_pairs} do
      header_timeslot = Constants.ticket_submission_end() - 1
      [ticket] = create_valid_tickets(1, state, key_pairs)

      # Generate the output hash using ring_vrf_output
      {secret, _} = List.first(key_pairs)
      public_keys = Enum.map(state.curr_validators, & &1.bandersnatch)

      context =
        SigningContexts.jam_ticket_seal() <> state.entropy_pool.n2 <> <<ticket.entry_index>>

      output_hash = RingVrf.ring_vrf_output(public_keys, secret, 0, context)

      # Add the output hash to gamma_a
      safrole_with_overlap = %{
        state.safrole
        | ticket_accumulator: [
            %System.State.SealKeyTicket{id: output_hash, entry_index: ticket.entry_index}
            | state.safrole.ticket_accumulator
          ]
      }

      assert {:error, "Ticket hash overlap with existing tickets"} ==
               TicketProof.validate_tickets(
                 [ticket],
                 header_timeslot,
                 header_timeslot - 1,
                 state.entropy_pool,
                 safrole_with_overlap
               )
    end
  end
end
