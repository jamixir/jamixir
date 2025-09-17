defmodule System.Validators.Safrole do
  use SelectiveMock
  alias Block.Header
  alias System.State.{EntropyPool, Safrole}
  alias Util.Time

  # Formula (6.27) v0.7.2
  mockable valid_epoch_marker(
             %Header{timeslot: timeslot, epoch_mark: epoch_marker},
             state_timeslot,
             %EntropyPool{n0: n0, n1: n1},
             pending_
           ) do
    new_epoch? = Time.new_epoch?(state_timeslot, timeslot)

    cond do
      new_epoch? and epoch_marker == new_epoch_marker(n0, n1, pending_) ->
        :ok

      not new_epoch? and is_nil(epoch_marker) ->
        :ok

      true ->
        {:error, "Invalid epoch marker"}
    end
  end

  def new_epoch_marker(n0, n1, pending_) do
    {n0, n1, for(v <- pending_, do: {v.bandersnatch, v.ed25519})}
  end

  def mock(:valid_epoch_marker, _), do: :ok
  def mock(:valid_winning_tickets_marker, _), do: :ok

  # Formula (6.28) v0.7.2
  mockable valid_winning_tickets_marker(
             %Header{timeslot: timeslot, winning_tickets_marker: winning_tickets_marker},
             state_timeslot,
             %Safrole{ticket_accumulator: gamma_a}
           ) do
    {new_epoch_index, new_epoch_phase} = Time.epoch_index_and_phase(timeslot)
    {prev_epoch_index, prev_epoch_phase} = Time.epoch_index_and_phase(state_timeslot)

    if new_epoch_index == prev_epoch_index and
         prev_epoch_phase < Constants.ticket_submission_end() and
         new_epoch_phase >= Constants.ticket_submission_end() and
         length(gamma_a) == Constants.epoch_length() do
      if winning_tickets_marker == Safrole.outside_in_sequencer(gamma_a),
        do: :ok,
        else: {:error, "Invalid winning tickets marker"}
    else
      if winning_tickets_marker == nil,
        do: :ok,
        else: {:error, "Invalid winning tickets marker"}
    end
  end
end
