defmodule Block.Extrinsic.TicketProof do
  @moduledoc """
  represent a ticket proof.
  Formula (74) v0.4.5

  the signature is construct out of 3 parts:
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
          attempt: 0 | 1,
          # as N = 2
          # p
          signature: Types.bandersnatch_ringVRF_proof_of_knowledge()
        }

  defstruct attempt: 0, signature: <<>>

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
         # Formula (77) v0.4.5
         :ok <-
           (case Collections.validate_unique_and_ordered(n, & &1.id) do
              {:error, :not_in_order} -> {:error, :bad_ticket_order}
              r -> r
            end) do
      # Formula (78) v0.4.5
      Safrole.validate_new_tickets(safrole, MapSet.new(n, & &1.id))
    end
  end

  # Formula (75) v0.4.5
  defp validate_ticket_count(tickets, header_timeslot) do
    epoch_phase = Time.epoch_phase(header_timeslot)

    cond do
      # m' < Y
      epoch_phase < Constants.ticket_submission_end() and
          length(tickets) <= Constants.max_tickets_pre_extrinsic() ->
        # |ET| <= K
        :ok

      # |ET| == 0
      epoch_phase >= Constants.ticket_submission_end() and Enum.empty?(tickets) ->
        :ok

      true ->
        {:error, :unexpected_ticket}
    end
  end

  # Formula (74) v0.4.5 - r ∈ NN
  @spec validate_entry_indices(list(t())) :: :ok | {:error, String.t()}
  defp validate_entry_indices(ticket_proofs) do
    if Enum.all?(ticket_proofs, &(&1.attempt in 0..(Constants.tickets_per_validator() - 1))) do
      :ok
    else
      {:error, "Invalid entry index"}
    end
  end

  # Formula (74) v0.4.5
  # Formula (76) v0.4.5
  @spec construct_n(list(t()), binary(), Types.bandersnatch_ring_root()) ::
          {:ok, list(SealKeyTicket.t())} | {:error, String.t()}
  mockable construct_n(ticket_proofs, eta2, epoch_root) do
    Enum.reduce_while(ticket_proofs, {:ok, []}, fn %TicketProof{
                                                     attempt: r,
                                                     signature: proof
                                                   },
                                                   {:ok, acc} ->
      context = SigningContexts.jam_ticket_seal() <> eta2 <> <<r>>

      case RingVrf.ring_vrf_verify(epoch_root, context, <<>>, proof) do
        {:ok, output_hash} ->
          {:cont, {:ok, acc ++ [%SealKeyTicket{id: output_hash, attempt: r}]}}

        _ ->
          {:halt, {:error, :bad_ticket_proof}}
      end
    end)
  end

  def mock(:validate, _), do: :ok
  def mock(:construct_n, _), do: {:ok, [%SealKeyTicket{attempt: 0, id: <<>>}]}

  use JsonDecoder

  defimpl Encodable do
    use Codec.Encoder

    def encode(%Block.Extrinsic.TicketProof{} = tp) do
      e({tp.attempt, tp.signature})
    end
  end

  use Sizes

  def decode(bin) do
    <<attempt::integer, signature::binary-size(@bandersnatch_proof_size), rest::binary>> = bin
    {%__MODULE__{attempt: attempt, signature: signature}, rest}
  end
end
