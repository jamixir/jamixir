defmodule System.State.Safrole do
  @moduledoc """
  Safrole  state, as specified in section 6.1 of the GP.
  """
  alias Block.Header
  alias Codec.{Decoder, Encoder}
  alias System.State.{EntropyPool, Safrole, SealKeyTicket, Validator}
  alias Util.{Hash, Time}

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
    %Safrole{
      safrole
      | current_epoch_slot_sealers:
          get_posterior_epoch_slot_sealers(
            header,
            timeslot,
            safrole,
            entropy_pool,
            curr_validators
          )
    }
  end

  # Formula (69) v0.3.4
  def get_posterior_epoch_slot_sealers(
        %Header{timeslot: new_timeslot},
        timeslot,
        safrole,
        %EntropyPool{n2: n2},
        curr_validators
      ) do
    # Formula (69) v0.3.4 - second arm
    if Time.epoch_index(new_timeslot) == Time.epoch_index(timeslot) do
      safrole.current_epoch_slot_sealers
    else
      # Formula (69) v0.3.4 - if e' = e + 1 ∧ m ≥ Y ∧ ∣γa∣ = E
      if Time.epoch_index(new_timeslot) == Time.epoch_index(timeslot) + 1 and
           length(safrole.ticket_accumulator) == Constants.epoch_length() and
           Time.epoch_phase(timeslot) >= Constants.ticket_submission_end() do
        outside_in_sequencer(safrole.current_epoch_slot_sealers)
      else
        fallback_key_sequence(n2, curr_validators)
      end
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
  @spec fallback_key_sequence(Types.hash(), list(Validator.t())) ::
          list(Types.bandersnatch_key())
  def fallback_key_sequence(n2, current_validators) do
    validator_set_size = length(current_validators)

    0..(Constants.epoch_length() - 1)
    |> Enum.map(fn i ->
      validator_index = generate_index_using_entropy(n2, i, validator_set_size)
      IO.inspect(validator_index)
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
    encoded_i = Encoder.encode_le(i, 4)
    concat = entropy <> encoded_i
    hashed = Hash.blake2b_n(concat, 4)
    decdoded = Decoder.decode_integer(hashed)

    rem = decdoded |> rem(validator_set_size)
    rem
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

  @spec validate_new_tickets(t(), MapSet.t()) :: :ok | {:error, String.t()}
  def validate_new_tickets(%__MODULE__{ticket_accumulator: ticket_accumulator}, new_ticket_hashes) do
    accumulator_set = MapSet.new(ticket_accumulator, & &1.id)

    if MapSet.disjoint?(accumulator_set, new_ticket_hashes) do
      :ok
    else
      {:error, "Ticket hash overlap with existing tickets"}
    end
  end

  def from_json(json) do
    %__MODULE__{
      pending: json.pending |> Enum.map(&Validator.from_json/1),
      epoch_root: Utils.hex_to_binary(json.epoch_root),
      current_epoch_slot_sealers:
        json.current_epoch_slot_sealers |> Enum.map(&Utils.hex_to_binary/1),
      ticket_accumulator: json.ticket_accumulator
    }
  end
end
