defmodule Block.Extrinsic.TicketProofTestHelper do
  alias Block.Extrinsic.TicketProof

  def create_valid_tickets(count, state, key_pairs) do
    for i <- 0..(count - 1) do
      keypair = Enum.at(key_pairs, rem(i, length(key_pairs)))
      attempt = rem(i, 2)
      {proof, _} = create_valid_proof(state, keypair, i, attempt)
      %TicketProof{attempt: attempt, signature: proof}
    end
  end

  def create_valid_proof(state, keypair, prover_idx, attempt) do
    RingVrf.ring_vrf_sign(
      for(v <- state.curr_validators, do: v.bandersnatch),
      keypair,
      prover_idx,
      SigningContexts.jam_ticket_seal() <> state.entropy_pool.n2 <> <<attempt>>,
      <<>>
    )
  end
end
