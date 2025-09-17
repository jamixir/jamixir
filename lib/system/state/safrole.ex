defmodule System.State.Safrole do
  alias Block.Extrinsic.TicketProof
  alias Block.Header
  import Codec.{Encoder, Decoder}
  alias Codec.VariableSize
  alias System.State.{EntropyPool, RotateKeys, Safrole, SealKeyTicket, Validator}
  use SelectiveMock
  alias Util.{Hash, Time}

  @type t :: %__MODULE__{
          # Formula (6.7) v0.7.0
          # γP
          pending: list(Validator.t()),
          # Formula (6.4) v0.7.0
          # γZ
          epoch_root: Types.bandersnatch_ring_root(),
          # Formula (6.5) v0.7.0
          # γS
          slot_sealers: list(SealKeyTicket.t()) | list(Types.hash()),
          # Formula (6.5) v0.7.0
          # γA
          ticket_accumulator: list(SealKeyTicket.t())
        }

  # Formula (6.3) v0.7.0
  defstruct pending: [], epoch_root: <<>>, slot_sealers: [], ticket_accumulator: []

  def transition(
        %Block{header: h, extrinsic: e},
        state,
        judgements_,
        rotated_history_entropy_pool
      ) do
    # κ' Formula (4.9) v0.7.2
    # λ' Formula (4.10) v0.7.2
    # γ'(γ_k, γ_z) Formula (4.7) v0.7.2
    with {pending_, curr_validators_, prev_validators_, epoch_root_} <-
           RotateKeys.rotate_keys(h, state, judgements_),
         :ok <-
           System.Validators.Safrole.valid_epoch_marker(
             h,
             state.timeslot,
             state.entropy_pool,
             pending_
           ),
         # Formula (6.24) v0.7.0
         epoch_slot_sealers_ =
           Safrole.get_epoch_slot_sealers_(
             h,
             state.timeslot,
             state.safrole,
             rotated_history_entropy_pool,
             curr_validators_
           ),
         # Formula (6.34) v0.7.0
         {:ok, ticket_accumulator_} <-
           Safrole.calculate_ticket_accumulator_(
             h.timeslot,
             state.timeslot,
             e.tickets,
             state.safrole,
             rotated_history_entropy_pool
           ) do
      {curr_validators_, prev_validators_,
       %Safrole{
         pending: pending_,
         epoch_root: epoch_root_,
         slot_sealers: epoch_slot_sealers_,
         ticket_accumulator: ticket_accumulator_
       }}
    end
  end

  # Formula (6.24) v0.7.0
  def get_epoch_slot_sealers_(
        %Header{timeslot: timeslot_},
        timeslot,
        %Safrole{
          ticket_accumulator: ta,
          slot_sealers: slot_sealers
        },
        %EntropyPool{n2: n2_},
        curr_validators
      ) do
    # Formula (6.24) v0.7.0 - second arm
    if Time.epoch_index(timeslot_) == Time.epoch_index(timeslot) do
      slot_sealers
    else
      # Formula (6.24) v0.7.0 - if e' = e + 1 ∧ m ≥ Y ∧ ∣γa∣ = E
      if Time.epoch_index(timeslot_) == Time.epoch_index(timeslot) + 1 and
           length(ta) == Constants.epoch_length() and
           Time.epoch_phase(timeslot) >= Constants.ticket_submission_end() do
        outside_in_sequencer(ta)
      else
        fallback_key_sequence(n2_, curr_validators)
      end
    end
  end

  # Formula (6.34) v0.7.0
  # Formula (6.35) v0.7.0
  def calculate_ticket_accumulator_(
        header_timeslot,
        state_timeslot,
        tickets,
        %Safrole{
          epoch_root: cmtmnt,
          ticket_accumulator: ta
        },
        %EntropyPool{n2: n2}
      ) do
    {:ok, n} = TicketProof.construct_n(tickets, n2, cmtmnt)

    accumulator_ =
      if Time.new_epoch?(state_timeslot, header_timeslot) do
        n
      else
        n ++ ta
      end
      |> Enum.sort_by(& &1.id)
      |> Enum.take(Constants.epoch_length())

    if all_tickets_used?(n, accumulator_) do
      {:ok, accumulator_}
    else
      {:error, "Not all submitted tickets are in the new accumulator"}
    end
  end

  mockable all_tickets_used?(tickets, tickets_accumulator) do
    MapSet.subset?(MapSet.new(tickets), MapSet.new(tickets_accumulator))
  end

  def mock(:all_tickets_used?, _), do: true

  @doc """
  Z function: Outside-in sequencer function.
  Formula (6.25) v0.7.0
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
  Formula (6.26) v0.7.0
  Fallback key sequence function.
  selects an epoch’s worth of validator Bandersnatch keys
  """
  @spec fallback_key_sequence(Types.hash(), list(Validator.t())) ::
          list(Types.bandersnatch_key())
  def fallback_key_sequence(n2, current_validators) do
    validator_set_size = length(current_validators)

    for i <- 0..(Constants.epoch_length() - 1) do
      validator_index = generate_index_using_entropy(n2, i, validator_set_size)
      Enum.at(current_validators, validator_index).bandersnatch
    end
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
    (entropy <> e_le(i, 4))
    |> Hash.blake2b_n(4)
    |> de_le(4)
    |> rem(validator_set_size)
  end

  defimpl Encodable do
    import Codec.Encoder
    # Formula (D.2) v0.7.0 - C(4)
    # C(4) ↦ E(γ_P, γ_z, { 0 if γ_s ∈ ⟦T⟧_E, 1 if γ_s ∈ ⟦H⟧_E }, γ_s, ↕γ_a)
    def encode(safrole) do
      sealer_type =
        case safrole.slot_sealers do
          [] -> 0
          [%SealKeyTicket{} | _] -> 0
          _ -> 1
        end

      e(
        {safrole.pending, safrole.epoch_root, sealer_type, safrole.slot_sealers,
         vs(safrole.ticket_accumulator)}
      )
    end
  end

  def decode(bin) do
    {pending, rest} = decode_list(bin, Constants.validator_count(), Validator)
    <<epoch_root::b(bls_key), rest::binary>> = rest
    <<sealer_type::8, rest::binary>> = rest

    {slot_sealers, rest} =
      case sealer_type do
        0 -> decode_list(rest, Constants.epoch_length(), SealKeyTicket)
        1 -> decode_list(rest, :hash, Constants.epoch_length())
      end

    {ticket_accumulator, rest} =
      VariableSize.decode(rest, SealKeyTicket)

    {%__MODULE__{
       pending: pending,
       epoch_root: epoch_root,
       slot_sealers: slot_sealers,
       ticket_accumulator: ticket_accumulator
     }, rest}
  end

  @spec validate_new_tickets(t(), MapSet.t()) :: :ok | {:error, String.t()}
  def validate_new_tickets(%__MODULE__{ticket_accumulator: ticket_accumulator}, new_ticket_hashes) do
    accumulator_set = MapSet.new(ticket_accumulator, & &1.id)

    if MapSet.disjoint?(accumulator_set, new_ticket_hashes) do
      :ok
    else
      {:error, :duplicate_ticket}
    end
  end

  use JsonDecoder

  def json_mapping do
    %{
      pending: [Validator],
      slot_sealers: &parse_slot_sealers/1,
      ticket_accumulator: [SealKeyTicket]
    }
  end

  def to_json_mapping do
    %{
      pending: :gamma_k,
      slot_sealers: fn sealers ->
        case sealers do
          [%SealKeyTicket{} | _] -> [:gamma_s, :tickets]
          _ -> [:gamma_s, :keys]
        end
      end,
      ticket_accumulator: :gamma_a,
      epoch_root: :gamma_z
    }
  end

  defp parse_slot_sealers(%{keys: keys}) do
    keys |> Enum.map(&JsonDecoder.from_json/1)
  end

  defp parse_slot_sealers(%{tickets: tickets}) do
    tickets |> Enum.map(&SealKeyTicket.from_json/1)
  end
end
