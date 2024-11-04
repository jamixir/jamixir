defmodule System.Validators.Safrole do
  use SelectiveMock
  alias Block.Header
  alias System.State.Safrole
  alias Util.Time

  # Formula (72) v0.4.5
  mockable valid_epoch_marker(
             %Header{timeslot: timeslot, epoch_mark: epoch_marker},
             state_timeslot,
             n1_,
             pending_
           ) do
    new_epoch? = Time.new_epoch?(state_timeslot, timeslot)

    cond do
      new_epoch? and epoch_marker == {n1_, for(v <- pending_, do: v.bandersnatch)} ->
        :ok

      not new_epoch? and is_nil(epoch_marker) ->
        :ok

      true ->
        {:error, "Invalid epoch marker"}
    end
  end

  def mock(:valid_epoch_marker, _), do: :ok
  def mock(:valid_winning_tickets_marker, _), do: :ok

  # Formula (73) v0.4.5
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
