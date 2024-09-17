defmodule Block.Extrinsic.TicketProof do
  @moduledoc """
  represent a ticket proof.
  Formula (74) v0.3.4

  the ticket_validity_proof is construct out of 3 parts:
  ring root - gamma_z, the current epoch root
  message - empty list
  context - $jam_ticket_seal ^ η2'(posterior_entropy_pool.n2) ^ [r (the ticket entry index)]
  """

  alias System.State.EntropyPool
  alias Util.Time

  @type t :: %__MODULE__{
          # r
          entry_index: 0 | 1,
          # as N = 2
          # p
          ticket_validity_proof: Types.bandersnatch_ringVRF_proof_of_knowledge()
        }

  defstruct entry_index: 0, ticket_validity_proof: <<>>

  # Formula (74) v0.3.4
  @spec validate_tickets(
          list(t()),
          non_neg_integer(),
          non_neg_integer(),
          EntropyPool.t(),
          Types.bandersnatch_ring_root()
        ) ::
          :ok | {:error, String.t()}

  def validate_tickets(ticket_proofs, header_timeslot, state_timeslot, entropy_pool, epoch_root) do
    with {:ok, is_new_epoch} <- Time.new_epoch?(state_timeslot, header_timeslot),
         :ok <- validate_ticket_count(ticket_proofs, header_timeslot) do
      eta2 = if is_new_epoch, do: entropy_pool.n1, else: entropy_pool.n2
      Enum.reduce_while(ticket_proofs, :ok, &validate_ticket(&1, &2, eta2, epoch_root))
    end
  end

  defp validate_ticket(
         %__MODULE__{entry_index: index, ticket_validity_proof: proof},
         _acc,
         eta2,
         epoch_root
       )
       when index in [0, 1] do
    context = SigningContexts.jam_ticket_seal() <> eta2 <> <<index>>

    case RingVrf.ring_vrf_verify(epoch_root, context, <<>>, proof) do
      {:ok, _output_hash} -> {:cont, :ok}
      _ -> {:halt, {:error, "Invalid ticket validity proof"}}
    end
  end

  defp validate_ticket(%__MODULE__{entry_index: _index}, _acc, _eta2, _epoch_root) do
    {:halt, {:error, "Invalid entry index"}}
  end

  # Formula (75) v0.3.4
  defp validate_ticket_count(tickets, header_timeslot) do
    epoch_phase = Time.epoch_phase(header_timeslot)

    cond do
      epoch_phase < Constants.ticket_submission_end() and
          length(tickets) <= Constants.max_tickets() ->
        :ok

      epoch_phase >= Constants.ticket_submission_end() and Enum.empty?(tickets) ->
        :ok

      true ->
        {:error, "Invalid number of tickets for the current epoch phase"}
    end
  end
end
