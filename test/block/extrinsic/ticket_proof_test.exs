defmodule Block.Extrinsic.TicketProofTest do
  use ExUnit.Case
  alias Block.Extrinsic.TicketProof
  import Jamixir.Factory
  import Block.Extrinsic.TicketProofTestHelper
  import Block.Extrinsic.TicketProof
  import TestHelper

  defp create_and_sort_tickets(count, state, key_pairs) do
    for ticket <- create_valid_tickets(count, state, key_pairs),
        {:ok, output} = proof_output(ticket, state.entropy_pool.n2, state.safrole.epoch_root) do
      {output, ticket}
    end
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  setup_all do
    context = build(:genesis_state_with_safrole)
    context = put_in(context, [:h_t], Constants.ticket_submission_end() - 1)

    context =
      put_in(context, [:tickets], create_and_sort_tickets(5, context.state, context.key_pairs))

    {:ok, context}
  end

  describe "validate/5 - passing cases" do
    test "succeeds with single ticket before submission end", %{
      state: %{entropy_pool: entropy_pool, safrole: safrole, curr_validators: validators},
      key_pairs: [key | _],
      h_t: h_t
    } do
      {proof, _} = create_proof(validators, entropy_pool.n2, key, 0, 0)
      tickets = [%TicketProof{attempt: 0, signature: proof}]
      :ok = validate(tickets, h_t, h_t - 1, entropy_pool, safrole)
    end

    test "succeeds with multiple tickets before submission end", %{
      state: state,
      h_t: h_t,
      tickets: [t1, t2 | _]
    } do
      :ok = validate([t1, t2], h_t, h_t - 1, state.entropy_pool, state.safrole)
    end

    test "succeeds with empty tickets after submission end", %{state: state, h_t: h_t} do
      :ok = validate([], h_t, h_t - 1, state.entropy_pool, state.safrole)
    end
  end

  # tickets_per_validator
  setup_constants do
    def tickets_per_validator, do: 2
  end

  describe "create_new_epoch_tickets/3" do
    test "creates the correct number of tickets", %{state: state, key_pairs: [_, keypair | _]} do
      tickets = create_new_epoch_tickets(state, keypair, 1)

      for t <- tickets do
        {:ok, _} = proof_output(t, state.entropy_pool.n1, state.safrole.epoch_root)
      end

      assert length(tickets) == Constants.tickets_per_validator()
    end
  end

  describe "validate/5 - failing cases" do
    test "fails with too many tickets", %{state: state} do
      assert {:error, :unexpected_ticket} =
               validate(
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
      {valid_proof, _} =
        TicketProof.create_proof(
          state.curr_validators,
          state.entropy_pool.n2,
          List.first(key_pairs),
          0,
          0
        )

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

  describe "tickets_for_new_block/3" do
    @max_tickets Constants.max_tickets_pre_extrinsic()
    test "no tickets on epoch phase 0", %{state: state, tickets: tickets} do
      assert tickets_for_new_block(tickets, state, 0) == []
    end

    # |E_T| = m′ >= Y
    test "no tickets after contest ends", %{state: state, tickets: tickets} do
      assert tickets_for_new_block(tickets, state, Constants.ticket_submission_end()) == []
    end

    test "sorts tickets correctly", %{state: state, tickets: tickets} do
      assert length(tickets) > @max_tickets
      # make sure existing accumulator is empty to take all new tickets
      state = %{state | safrole: %{state.safrole | ticket_accumulator: []}}

      tickets = tickets_for_new_block(tickets, state, Constants.ticket_submission_end() - 1)
      assert length(tickets) == @max_tickets

      assert tickets ==
               Enum.sort_by(
                 tickets,
                 &(proof_output(&1, state.entropy_pool.n2, state.safrole.epoch_root) |> elem(1))
               )
    end

    test "when existing tickets don't fit the pool because high ids", %{
      state: state,
      tickets: tickets
    } do
      full_accumulator =
        for low_id <- 0..(Constants.epoch_length() - 1) do
          %System.State.SealKeyTicket{id: <<low_id::256>>}
        end

      safrole = %{state.safrole | ticket_accumulator: full_accumulator}
      state = %{state | safrole: safrole}
      assert tickets_for_new_block(tickets, state, 1) == []
    end

    test "don't add tickets already in state", %{state: state, tickets: [t1, t2 | _]} do
      safrole_with_existing_ticket = %{
        state.safrole
        | ticket_accumulator: [
            %System.State.SealKeyTicket{
              id: proof_output(t1, state.entropy_pool.n2, state.safrole.epoch_root) |> elem(1),
              attempt: t1.attempt
            }
          ]
      }

      tickets =
        tickets_for_new_block([t1, t2], %{state | safrole: safrole_with_existing_ticket}, 1)

      assert tickets == [t2]
    end

    test "don't add tickets with invalid proof", %{state: state, tickets: [t1, t2 | _]} do
      invalid_ticket = %TicketProof{attempt: t1.attempt, signature: <<0, 1, 2>>}
      tickets = tickets_for_new_block([invalid_ticket, t2], state, 1)
      assert tickets == [t2]
    end

    test "don't add tickets with state invalid root", %{state: state, tickets: tickets} do
      state = %{state | safrole: %{state.safrole | epoch_root: <<0, 0, 0>>}}
      tickets = tickets_for_new_block(tickets, state, 1)
      assert tickets == []
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
