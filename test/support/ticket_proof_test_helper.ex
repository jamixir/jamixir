defmodule Block.Extrinsic.TicketProofTestHelper do
  alias Block.Extrinsic.TicketProof

  def create_valid_tickets(count, state, key_pairs) do
    for i <- 0..(count - 1) do
      keypair = Enum.at(key_pairs, rem(i, length(key_pairs)))
      attempt = rem(i, Constants.tickets_per_validator() - 1)

      {proof, _} =
        TicketProof.create_proof(
          state.curr_validators,
          state.entropy_pool.n2,
          keypair,
          i,
          attempt
        )

      %TicketProof{attempt: attempt, signature: proof}
    end
  end
end
