defmodule Block.Extrinsic.TicketProof do
  @moduledoc """
  represent a ticket proof.
  Formula (74) v0.4.1

  the ticket_validity_proof is construct out of 3 parts:
  ring root - gamma_z, the current epoch root
  message - empty list
  context - $jam_ticket_seal ^ η2'(entropy_pool_.n2) ^ [r (the ticket entry index)]
  """
  alias Block.Extrinsic.TicketProof
  alias System.State.{EntropyPool, Safrole, SealKeyTicket}
  alias Util.{Collections, Time}
  use SelectiveMock

  @type t :: %__MODULE__{
          # r
          entry_index: 0 | 1,
          # as N = 2
          # p
          ticket_validity_proof: Types.bandersnatch_ringVRF_proof_of_knowledge()
        }

  defstruct entry_index: 0, ticket_validity_proof: <<>>

  @spec validate(
          list(t()),
          non_neg_integer(),
          non_neg_integer(),
          EntropyPool.t(),
          Types.bandersnatch_ring_root()
        ) ::
          :ok | {:error, String.t()}

  mockable validate(ticket_proofs, header_timeslot, state_timeslot, entropy_pool, safrole) do
    with is_new_epoch <- Time.new_epoch?(state_timeslot, header_timeslot),
         :ok <- validate_ticket_count(ticket_proofs, header_timeslot),
         :ok <- validate_entry_indices(ticket_proofs),
         {:ok, n} <-
           construct_n(
             ticket_proofs,
             if(is_new_epoch, do: entropy_pool.n1, else: entropy_pool.n2),
             safrole.epoch_root
           ),
         # Formula (77) v0.4.1
         :ok <- Collections.validate_unique_and_ordered(n, & &1.id) do
      # Formula (78) v0.4.1
      Safrole.validate_new_tickets(safrole, MapSet.new(n, & &1.id))
    end
  end

  # Formula (75) v0.4.1
  defp validate_ticket_count(tickets, header_timeslot) do
    epoch_phase = Time.epoch_phase(header_timeslot)

    cond do
      # m' < Y
      epoch_phase < Constants.ticket_submission_end() and
          length(tickets) <= Constants.max_tickets() ->
        # |ET| <= K
        :ok

      # |ET| == 0
      epoch_phase >= Constants.ticket_submission_end() and Enum.empty?(tickets) ->
        :ok

      true ->
        {:error, "Invalid number of tickets for the current epoch phase"}
    end
  end

  # Formula (74) v0.4.1 - r ∈ NN
  @spec validate_entry_indices(list(t())) :: :ok | {:error, String.t()}
  defp validate_entry_indices(ticket_proofs) do
    if Enum.all?(ticket_proofs, &(&1.entry_index in [0, 1])) do
      :ok
    else
      {:error, "Invalid entry index"}
    end
  end

  # Formula (74) v0.4.1
  # Formula (76) v0.4.1
  @spec construct_n(list(t()), binary(), Types.bandersnatch_ring_root()) ::
          {:ok, list(SealKeyTicket.t())} | {:error, String.t()}
  mockable construct_n(ticket_proofs, eta2, epoch_root) do
    Enum.reduce_while(ticket_proofs, {:ok, []}, fn %TicketProof{
                                                     entry_index: r,
                                                     ticket_validity_proof: proof
                                                   },
                                                   {:ok, acc} ->
      context = SigningContexts.jam_ticket_seal() <> eta2 <> <<r>>

      case RingVrf.ring_vrf_verify(epoch_root, context, <<>>, proof) do
        {:ok, output_hash} ->
          {:cont, {:ok, acc ++ [%SealKeyTicket{id: output_hash, entry_index: r}]}}

        _ ->
          {:halt, {:error, "Invalid ticket validity proof"}}
      end
    end)
  end

  def mock(:validate, _), do: :ok
  def mock(:construct_n, _), do: {:ok, [%SealKeyTicket{entry_index: 0, id: <<>>}]}

  use JsonDecoder

  def json_mapping, do: %{entry_index: :attempt, ticket_validity_proof: :signature}

  defimpl Encodable do
    def encode(%Block.Extrinsic.TicketProof{} = tp) do
      Codec.Encoder.encode({
        tp.entry_index,
        tp.ticket_validity_proof
      })
    end
  end
end
