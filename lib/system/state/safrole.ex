defmodule System.State.Safrole do
  @moduledoc """
  Safrole  state, as specified in section 6.1 of the GP.
  """
  alias System.State.{SealKeyTicket, Validator, EntropyPool, Safrole}
  alias Block.Header
  alias Util.Hash
  alias Codec.{Encoder, Decoder}

  @type t :: %__MODULE__{
          # Formula (52) v0.3.4
          # gamma_k
          pending: list(Validator.t()),
          # Formula (49) v0.3.4
          # gamma_z
          epoch_root: Types.bandersnatch_ring_root(),
          # Formula (50) v0.3.4
          # gamma_s
          current_epoch_slot_sealers: list(SealKeyTicket.t()) | list(Types.hash()),
          # Formula (50) v0.3.4
          # gamma_a
          ticket_accumulator: list(SealKeyTicket.t())
        }

  # Formula (48) v0.3.4
  defstruct pending: [], epoch_root: <<>>, current_epoch_slot_sealers: [], ticket_accumulator: []

  def posterior_safrole(
        %Header{} = header,
        timeslot,
        _tickets,
        safrole,
        entropy_pool,
        curr_validators
      ) do
    # Formula (69) v0.3.4
    posterior_epoch_slot_sealers =
      get_posterior_epoch_slot_sealers(header, timeslot, safrole, entropy_pool, curr_validators)

    # i = γs′ [Ht ]↺
    # candidate_slot_sealer =
    #   Enum.at(posterior_epoch_slot_sealers, rem(header.timeslot, Constants.epoch_length()))

    %Safrole{
      safrole
      | current_epoch_slot_sealers: posterior_epoch_slot_sealers
    }

    # with :ok <- validate_candidate(candidate_slot_sealer, header, entropy_pool, curr_validators) do

    #
    # else
    #   {:error, reason} -> {:error, reason}
    # end
  end

  # @spec validate_candidate(
  #         binary() | System.State.SealKeyTicket.t(),
  #         Block.Header.t(),
  #         System.State.EntropyPool.t(),
  #         any()
  #       ) :: :ok | {:error, any()}
  # def validate_candidate(
  #       %SealKeyTicket{} = candidate_slot_sealer,
  #       header,
  #       entropy_pool,
  #       curr_validators
  #     ) do
  #   SealKeyTicket.validate_candidate(candidate_slot_sealer, header, entropy_pool, curr_validators)
  # end

  # def validate_candidate(candidate_hash, header, entropy_pool, curr_validators)
  #     when is_binary(candidate_hash) do
  #   validate_candidate_hash(candidate_hash, header, entropy_pool, curr_validators)
  # end

  # defp validate_candidate_hash(
  #        candidate_hash,
  #        %Header{block_author_key_index: h_i, block_seal: h_s} = h,
  #        %EntropyPool{history: [_, _, eta3 | _]},
  #        curr_validators
  #      ) do
  #   # Retrieve the bandersnatch key for the current block author
  #   with %System.State.Validator{bandersnatch: key} <- Enum.at(curr_validators, h_i),
  #        true <- key == candidate_hash,
  #        message = Header.unsigned_serialize(h),
  #        aux_data = SigningContexts.jam_fallback_seal() <> eta3,
  #        {:ok, _} <- Util.Bandersnatch._verify(key, message, aux_data, h_s) do
  #     :ok
  #   else
  #     nil ->
  #       {:error, :invalid_validator_index}

  #     false ->
  #       {:error, :invalid_candidate_hash}

  #     {:error, reason} ->
  #       {:error, reason}
  #   end
  # end

  # Formula (69) v0.3.4
  def get_posterior_epoch_slot_sealers(
        %Header{timeslot: new_timeslot},
        timeslot,
        safrole,
        entropy_pool,
        curr_validators
      ) do
    case System.HeaderSealsVerifier.determine_ticket_or_fallback(
           new_timeslot,
           timeslot,
           safrole.ticket_accumulator
         ) do
      :ticket_same ->
        safrole.current_epoch_slot_sealers

      :ticket_shuffle ->
        outside_in_sequencer(safrole.current_epoch_slot_sealers)

      :fallback ->
        fallback_key_sequence(entropy_pool, curr_validators)
    end
  end

  @doc """
  Z function: Outside-in sequencer function.
  Reorders the list by alternating between the first and last elements.
  Formula (70) v0.3.4
  """
  @spec outside_in_sequencer([SealKeyTicket.t()]) :: [SealKeyTicket.t()]
  def outside_in_sequencer(tickets) do
    do_z(tickets, [])
  end

  defp do_z([], acc), do: acc
  defp do_z([single], acc), do: acc ++ [single]

  defp do_z([first | rest], acc) do
    last = List.last(rest)
    middle = Enum.slice(rest, 0, length(rest) - 1)
    do_z(middle, acc ++ [first, last])
  end

  @doc """
  Formula (71) v0.3.4
  Fallback key sequence function.
  selects an epoch’s worth of validator Bandersnatch keys
  """
  @spec fallback_key_sequence(EntropyPool.t(), list(Validator.t())) ::
          list(Types.bandersnatch_key())
  def fallback_key_sequence(%EntropyPool{history: [_, eta2 | _]}, current_validators) do
    validator_set_size = length(current_validators)

    0..(Constants.epoch_length() - 1)
    |> Enum.map(fn i ->
      validator_index = generate_index_using_entropy(eta2, i, validator_set_size)
      Enum.at(current_validators, validator_index).bandersnatch
    end)
  end

  @doc """
  Generate an index in the range [0, validator_set_size) using entropy.
  """
  @spec generate_index_using_entropy(binary(), integer()) :: integer()
  def generate_index_using_entropy(entropy, i) do
    generate_index_using_entropy(entropy, i, Constants.validator_count())
  end

  @spec generate_index_using_entropy(binary(), integer(), integer()) :: integer()
  def generate_index_using_entropy(entropy, i, validator_set_size) do
    entropy
    |> Kernel.<>(Encoder.encode_le(i, 4))
    |> Hash.blake2b_n(4)
    |> Decoder.decode_le(4)
    |> rem(validator_set_size)
  end

  defimpl Encodable do
    alias Codec.VariableSize
    # Equation (292) - C(4)
    # C(4) ↦ E(γk, γz, { 0 if γs ∈ ⟦C⟧E 1 if γs ∈ ⟦HB⟧E }, γs, ↕γa)
    def encode(safrole) do
      sealer_type =
        case safrole.current_epoch_slot_sealers do
          [] -> 0
          [%SealKeyTicket{} | _] -> 0
          _ -> 1
        end

      Codec.Encoder.encode({
        safrole.pending,
        safrole.epoch_root,
        sealer_type,
        safrole.current_epoch_slot_sealers,
        VariableSize.new(safrole.ticket_accumulator)
      })
    end
  end
end
