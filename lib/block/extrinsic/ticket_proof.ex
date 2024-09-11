defmodule Block.Extrinsic.TicketProof do
  @moduledoc """
  represent a ticket proof.
  Formula (74) v0.3.4

  the ticket_validity_proof is construct out of 3 parts:
  ring root - gamma_z, the current epoch root
  message - empty list
  context - $jam_ticket_seal ^ η2'(posterior_entropy_pool.n2) ^ [r (the ticket entry index)]



  """
  @type t :: %__MODULE__{
          # r
          entry_index: 0 | 1,
          # as N = 2
          # p
          ticket_validity_proof: Types.bandersnatch_ringVRF_proof_of_knowledge()
        }

  defstruct entry_index: 0, ticket_validity_proof: <<>>
end
