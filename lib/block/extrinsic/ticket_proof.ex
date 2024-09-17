defmodule Block.Extrinsic.TicketProof do
  @moduledoc """
  represent a ticket proof.
  Formula (74) v0.3.4

  the ticket_validity_proof is construct out of 3 parts:
  ring root - gamma_z, the current epoch root
  message - empty list
  context - $jam_ticket_seal ^ η2'(posterior_entropy_pool.n2) ^ [r (the ticket entry index)]
  """

  alias System.State.{EntropyPool, Safrole}
  alias Util.{Collections, Time}

  @type t :: %__MODULE__{
          # r
          entry_index: 0 | 1,
          # as N = 2
          # p
          ticket_validity_proof: Types.bandersnatch_ringVRF_proof_of_knowledge()
        }

  defstruct entry_index: 0, ticket_validity_proof: <<>>

  @spec validate_tickets(
          list(t()),
          non_neg_integer(),
          non_neg_integer(),
          EntropyPool.t(),
          Types.bandersnatch_ring_root()
        ) ::
          :ok | {:error, String.t()}

  def validate_tickets(ticket_proofs, header_timeslot, state_timeslot, entropy_pool, safrole) do
    with {:ok, is_new_epoch} <- Time.new_epoch?(state_timeslot, header_timeslot),
         :ok <- validate_ticket_count(ticket_proofs, header_timeslot),
         :ok <- validate_entry_indices(ticket_proofs),
         {:ok, n} <-
           construct_n(
             ticket_proofs,
             if(is_new_epoch, do: entropy_pool.n1, else: entropy_pool.n2),
             safrole.epoch_root
           ),
         # Formula (77) v0.3.4
         :ok <- Collections.validate_unique_and_ordered(n, &elem(&1, 0)),
         # Formula (78) v0.3.4
         :ok <- Safrole.validate_new_tickets(safrole, MapSet.new(n, &elem(&1, 0))) do
      :ok
    end
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

  # Formula (74) v0.3.4
  @spec validate_entry_indices(list(t())) :: :ok | {:error, String.t()}
  defp validate_entry_indices(ticket_proofs) do
    if Enum.all?(ticket_proofs, &(&1.entry_index in [0, 1])) do
      :ok
    else
      {:error, "Invalid entry index"}
    end
  end

  # Formula (74) v0.3.4
  # Formula (76) v0.3.4
  @spec construct_n(list(t()), binary(), Types.bandersnatch_ring_root()) ::
          {:ok, list({binary(), 0 | 1})} | {:error, String.t()}
  defp construct_n(ticket_proofs, eta2, epoch_root) do
    Enum.reduce_while(ticket_proofs, {:ok, []}, fn %__MODULE__{
                                                     entry_index: r,
                                                     ticket_validity_proof: proof
                                                   },
                                                   {:ok, acc} ->
      context = SigningContexts.jam_ticket_seal() <> eta2 <> <<r>>

      case RingVrf.ring_vrf_verify(epoch_root, context, <<>>, proof) do
        {:ok, output_hash} -> {:cont, {:ok, acc ++ [{output_hash, r}]}}
        _ -> {:halt, {:error, "Invalid ticket validity proof"}}
      end
    end)
  end
end
