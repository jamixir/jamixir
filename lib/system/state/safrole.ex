defmodule System.State.Safrole do
  @moduledoc """
  Sarole  state, as specified in section 6.1 of the GP.
  """
  alias System.State.SealKeyTicket
  alias System.State.Validator

  @type t :: %__MODULE__{
          # gamma_k
          pending: list(Validator.t()),
          # Formula (49) v0.3.4
          # gamma_z
          epoch_root: <<_::1152>>,
          # gamma_s
          current_epoch_slot_sealers: list(SealKeyTicket.t()) | list(<<_::256>>),
          # gamma_a
          ticket_accumulator: list(SealKeyTicket.t())
        }

  # Formula (48) v0.3.4
  defstruct pending: [], epoch_root: <<>>, current_epoch_slot_sealers: [], ticket_accumulator: []

  def posterior_safrole(
        _header,
        _timeslot,
        _tickets,
        safrole,
        _next_validators,
        _entropy_pool,
        _curr_validators
      ) do
    # TODO
    safrole
  end

  @doc """
  Formula (70) v0.3.4
  Z function: Outside-in sequencer function.
  Reorders the list by alternating between the first and last elements.
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
