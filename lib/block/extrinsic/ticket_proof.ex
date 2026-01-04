defmodule Block.Extrinsic.TicketProof do
  @moduledoc """
  represent a ticket proof.
  Formula (6.29) v0.7.2

  the signature is construct out of 3 parts:
  ring root - gamma_z, the current epoch root
  message - empty list
  context - $jam_ticket_seal ^ η2'(entropy_pool_.n2) ^ [r (the ticket entry index)]
  """
  alias Block.Extrinsic.TicketProof
  alias System.State.{EntropyPool, Safrole, SealKeyTicket}
  alias Util.{Collections, Time}
  alias System.State.Validator
  use SelectiveMock
  import RangeMacros

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
         # Formula (6.32) v0.7.2
         :ok <-
           (case Collections.validate_unique_and_ordered(n, & &1.id) do
              {:error, :duplicates} -> {:error, :duplicate_tickets}
              {:error, :not_in_order} -> {:error, :bad_ticket_order}
              r -> r
            end) do
      # Formula (6.34) v0.7.2
      Safrole.validate_new_tickets(safrole, MapSet.new(n, & &1.id))
    end
  end

  # Formula (6.30) v0.7.2
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

  # Formula (6.29) v0.7.2 - r ∈ ℕ_N
  @spec validate_entry_indices(list(t())) :: :ok | {:error, String.t()}
  defp validate_entry_indices(ticket_proofs) do
    valid_range = 0..(Constants.tickets_per_validator() - 1)

    if Enum.all?(ticket_proofs, &(&1.attempt in valid_range)) do
      :ok
    else
      {:error, "Invalid entry index"}
    end
  end

  # Formula (6.29) v0.7.2
  # Formula (6.31) v0.7.2
  @spec construct_n(list(t()), binary(), Types.bandersnatch_ring_root()) ::
          {:ok, list(SealKeyTicket.t())} | {:error, String.t()}
  mockable construct_n(ticket_proofs, eta2, epoch_root) do
    Enum.reduce_while(ticket_proofs, {:ok, []}, fn %TicketProof{attempt: r} = ticket,
                                                   {:ok, acc} ->
      case proof_output(ticket, eta2, epoch_root) do
        {:ok, output_hash} ->
          {:cont, {:ok, acc ++ [%SealKeyTicket{id: output_hash, attempt: r}]}}

        _ ->
          {:halt, {:error, :bad_ticket_proof}}
      end
    end)
  end

  def create_proof([%Validator{} | _] = validators, entropy, keypair, prover_idx, attempt) do
    pub_keys = Enum.map(validators, & &1.bandersnatch)
    create_proof(pub_keys, entropy, keypair, prover_idx, attempt)
  end

  def create_proof([k1 | _] = pub_keys, entropy, keypair, prover_idx, attempt)
      when is_binary(k1) do
    context = SigningContexts.jam_ticket_seal() <> entropy <> <<attempt>>
    RingVrf.ring_vrf_sign(pub_keys, keypair, prover_idx, context, <<>>)
  end

  def create_new_epoch_tickets(state, keypair, prover_idx) do
    keys = Enum.map(state.next_validators, & &1.bandersnatch)

    Task.async_stream(from_0_to(Constants.tickets_per_validator()), fn i ->
      {p, _} = create_proof(keys, state.entropy_pool.n1, keypair, prover_idx, i)
      %TicketProof{signature: p, attempt: i}
    end)
    |> Enum.map(fn {:ok, ticket} -> ticket end)
  end

  def tickets_for_new_block(existing_tickets, state, epoch_phase) do
    entropy = state.entropy_pool.n2

    tickets_and_ids =
      for ticket <- existing_tickets,
          # TODO remove this constraint (needs re-calculate entropy and epoch_root)
          epoch_phase != 0,
          # Formula (6.30) v0.7.2
          epoch_phase < Constants.ticket_submission_end(),
          {result, id} = TicketProof.proof_output(ticket, entropy, state.safrole.epoch_root),
          result == :ok,
          seal = %SealKeyTicket{id: id, attempt: ticket.attempt},
          # Formula (6.33) v0.7.2
          not Enum.member?(state.safrole.ticket_accumulator, seal) do
        {ticket, id}
      end
      |> Enum.sort_by(fn {_ticket, id} -> id end)
      |> Enum.take(Constants.max_tickets_pre_extrinsic())

    existing_ids = Enum.map(state.safrole.ticket_accumulator, & &1.id)
    new_ids = Enum.map(tickets_and_ids, &elem(&1, 1))

    # Formula (6.35) v0.7.2
    all_ids =
      (existing_ids ++ new_ids)
      |> Enum.sort()
      |> Enum.take(Constants.epoch_length())
      |> MapSet.new()

    # Deduplicate tickets
    tickets_and_ids
    |> Enum.filter(fn {_t, id} -> MapSet.member?(all_ids, id) end)
    |> Enum.uniq_by(fn {t, _id} -> t end)
    |> Enum.map(fn {t, _id} -> t end)
  end

  def proof_output(%TicketProof{attempt: r, signature: proof}, eta2, epoch_root) do
    case RingVrf.ring_vrf_verify(epoch_root, ticket_context(eta2, r), <<>>, proof) do
      {:ok, output_hash} -> {:ok, output_hash}
      {:error, e} -> {:error, e}
      e -> {:error, e}
    end
  end

  def ticket_context(eta2, attempt) do
    SigningContexts.jam_ticket_seal() <> eta2 <> <<attempt::8>>
  end

  def mock(:validate, _), do: :ok
  def mock(:construct_n, _), do: {:ok, [%SealKeyTicket{attempt: 0, id: <<>>}]}

  use JsonDecoder

  defimpl Encodable do
    import Codec.Encoder

    def encode(%Block.Extrinsic.TicketProof{} = tp) do
      e({<<tp.attempt::8>>, tp.signature})
    end
  end

  use Sizes
  import Codec.Encoder

  def decode(bin) do
    <<attempt::integer, signature::b(bandersnatch_proof), rest::binary>> = bin
    {%__MODULE__{attempt: attempt, signature: signature}, rest}
  end
end
