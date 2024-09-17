defmodule Block.Extrinsic.TicketProofTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block.Extrinsic.TicketProof
  alias System.State.EntropyPool
  alias Util.Time

  setup_all do
    build(:genesis_state_with_safrole)
  end

  describe "validate_tickets/5" do
    test "succeeds when epoch_phase < ticket_submission_end and tickets <= max_tickets", %{
      state: state,
      key_pairs: key_pairs
    } do
      header_timeslot = Constants.ticket_submission_end() - 1
      {secret, _} = List.first(key_pairs)

      {proof, _} =
        RingVrf.ring_vrf_sign(
          Enum.map(state.curr_validators, & &1.bandersnatch),
          secret,
          0,
          SigningContexts.jam_ticket_seal() <> state.entropy_pool.n2 <> <<0>>,
          <<>>
        )

      assert :ok ==
               TicketProof.validate_tickets(
                 [%TicketProof{entry_index: 0, ticket_validity_proof: proof}],
                 header_timeslot,
                 header_timeslot - 1,
                 state.entropy_pool,
                 state.safrole.epoch_root
               )
    end

    test "succeeds when epoch_phase >= ticket_submission_end and tickets are empty", %{
      state: state
    } do
      assert :ok ==
               TicketProof.validate_tickets(
                 [],
                 Constants.ticket_submission_end(),
                 Constants.ticket_submission_end() - 1,
                 state.entropy_pool,
                 state.safrole.epoch_root
               )
    end

    test "fails with invalid timeslots (header_timeslot < state_timeslot)", %{state: state} do
      assert {:error, _} =
               TicketProof.validate_tickets(
                 [],
                 1,
                 101,
                 state.entropy_pool,
                 state.safrole.epoch_root
               )
    end

    test "fails with invalid number of tickets", %{state: state} do
      assert {:error, "Invalid number of tickets for the current epoch phase"} =
               TicketProof.validate_tickets(
                 List.duplicate(%TicketProof{}, Constants.max_tickets() + 1),
                 Constants.ticket_submission_end() - 1,
                 Constants.ticket_submission_end() - 2,
                 state.entropy_pool,
                 state.safrole.epoch_root
               )
    end

    test "fails with invalid entry index", %{state: state} do
      assert {:error, "Invalid entry index"} =
               TicketProof.validate_tickets(
                 [%TicketProof{entry_index: 2, ticket_validity_proof: <<1, 2, 3>>}],
                 499,
                 400,
                 state.entropy_pool,
                 state.safrole.epoch_root
               )
    end

    test "fails with invalid signature", %{state: state, key_pairs: key_pairs} do
      {secret, _} = List.first(key_pairs)

      {valid_proof, _} =
        RingVrf.ring_vrf_sign(
          Enum.map(state.curr_validators, & &1.bandersnatch),
          secret,
          0,
          SigningContexts.jam_ticket_seal() <> state.entropy_pool.n2 <> <<0>>,
          <<>>
        )

      <<first_byte, rest::binary>> = valid_proof
      invalid_proof = <<first_byte + 1>> <> rest

      assert {:error, "Invalid ticket validity proof"} =
               TicketProof.validate_tickets(
                 [%TicketProof{entry_index: 0, ticket_validity_proof: invalid_proof}],
                 1,
                 0,
                 state.entropy_pool,
                 state.safrole.epoch_root
               )
    end
  end
end
