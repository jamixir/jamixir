defmodule Block.Extrinsic.TicketProofTest do
  use ExUnit.Case
  import Jamixir.Factory
  import Block.Extrinsic.TicketProofTestHelper
  alias Block.Extrinsic.TicketProof

  defp create_and_sort_tickets(count, state, key_pairs) do
    for ticket <- create_valid_tickets(count, state, key_pairs),
        {:ok, output_hash} =
          RingVrf.ring_vrf_verify(
            state.safrole.epoch_root,
            SigningContexts.jam_ticket_seal() <> state.entropy_pool.n2 <> <<ticket.attempt>>,
            <<>>,
            ticket.signature
          ) do
      {output_hash, ticket}
    end
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  setup_all do
    build(:genesis_state_with_safrole)
  end

  describe "validate/5 - passing cases" do
    test "succeeds with single ticket before submission end", %{
      state: state,
      key_pairs: key_pairs
    } do
      {proof, _} = create_valid_proof(state, List.first(key_pairs), 0, 0)

      assert :ok ==
               TicketProof.validate(
                 [%TicketProof{attempt: 0, signature: proof}],
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
               TicketProof.validate(
                 tickets,
                 Constants.ticket_submission_end() - 1,
                 Constants.ticket_submission_end() - 2,
                 state.entropy_pool,
                 state.safrole
               )
    end

    test "succeeds with empty tickets after submission end", %{state: state} do
      assert :ok ==
               TicketProof.validate(
                 [],
                 Constants.ticket_submission_end(),
                 Constants.ticket_submission_end() - 1,
                 state.entropy_pool,
                 state.safrole
               )
    end
  end

  describe "validate/5 - failing cases" do
    test "fails with too many tickets", %{state: state} do
      assert {:error, :unexpected_ticket} =
               TicketProof.validate(
                 List.duplicate(%TicketProof{}, Constants.max_tickets_pre_extrinsic() + 1),
                 Constants.ticket_submission_end() - 1,
                 Constants.ticket_submission_end() - 2,
                 state.entropy_pool,
                 state.safrole
               )
    end

    test "fails with invalid entry index", %{state: state} do
      assert {:error, "Invalid entry index"} =
               TicketProof.validate(
                 [%TicketProof{attempt: 3, signature: <<1, 2, 3>>}],
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

      assert {:error, :bad_ticket_proof} =
               TicketProof.validate(
                 [%TicketProof{attempt: 0, signature: invalid_proof}],
                 1,
                 0,
                 state.entropy_pool,
                 state.safrole
               )
    end

    test "fails with non-unique tickets", %{state: state, key_pairs: key_pairs} do
      ticket = create_valid_tickets(1, state, key_pairs) |> List.first()

      assert {:error, :duplicates} ==
               TicketProof.validate(
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
      keypair = List.first(key_pairs)
      public_keys = for v <- state.curr_validators, do: v.bandersnatch

      context =
        SigningContexts.jam_ticket_seal() <> state.entropy_pool.n2 <> <<ticket.attempt>>

      output_hash = RingVrf.ring_vrf_output(public_keys, keypair, 0, context)

      # Add the output hash to gamma_a
      safrole_with_overlap = %{
        state.safrole
        | ticket_accumulator: [
            %System.State.SealKeyTicket{id: output_hash, attempt: ticket.attempt}
            | state.safrole.ticket_accumulator
          ]
      }

      assert {:error, :duplicate_ticket} ==
               TicketProof.validate(
                 [ticket],
                 header_timeslot,
                 header_timeslot - 1,
                 state.entropy_pool,
                 safrole_with_overlap
               )
    end
  end

  describe "encode / decode" do
    test "encode/decode" do
      ticket_proof = build(:ticket_proof)
      encoded = Encodable.encode(ticket_proof)
      {decoded, _} = TicketProof.decode(encoded)
      assert decoded == ticket_proof
    end
  end
end
