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

    %Safrole{
      safrole
      | current_epoch_slot_sealers: posterior_epoch_slot_sealers
    }
  end

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
