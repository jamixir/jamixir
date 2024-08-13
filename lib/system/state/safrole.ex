defmodule System.State.Safrole do
  @moduledoc """
  Sarole  state, as specified in section 6.1 of the GP.

  """
  alias System.State.Ticket
  alias System.State.Validator

  @type t :: %__MODULE__{
          # gamma_k
          pending: list(Validator.t()),
          # gamma_z
          epoch_root: <<_::1152>>,
          # gamma_s
          current_epoch_slot_sealers: list(Ticket.t()) | list(<<_::256>>),
          # gamma_a
          ticket_accumulator: list(Ticket.t())
        }

  defstruct pending: [], epoch_root: <<>>, current_epoch_slot_sealers: [], ticket_accumulator: []

  def posterior_safrole(
        _header,
        _timeslot,
        _tickets,
        _safrole,
        _next_validators,
        _entropy_pool,
        _curr_validators
      ) do
    # TODO
  end

  @doc """
  Formula (70) v0.3.4
  Z function: Outside-in sequencer function.
  Reorders the list by alternating between the first and last elements.
  """
  @spec outside_in_sequencer([Ticket.t()]) :: [Ticket.t()]
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
end
