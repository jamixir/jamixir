defmodule System.Validators.Safrole do
  use SelectiveMock
  alias Block.Header
  alias System.State.Safrole
  alias Util.Time

  # Formula (72) v0.3.4
  mockable valid_epoch_marker(
             %Header{
               timeslot: header_timeslot,
               epoch: epoch_marker
             },
             state_timeslot,
             posterior_n1,
             posterior_pending
           ) do
    is_new_epoch = Time.new_epoch?(state_timeslot, header_timeslot)

    cond do
      is_new_epoch and
          epoch_marker == {posterior_n1, Enum.map(posterior_pending, & &1.bandersnatch)} ->
        :ok

      not is_new_epoch and is_nil(epoch_marker) ->
        :ok

      true ->
        {:error, "Invalid epoch marker"}
    end
  end

  def mock(:valid_epoch_marker, _), do: :ok
  def mock(:valid_winning_tickets_marker, _), do: :ok

  # Formula (73) v0.3.4
  mockable valid_winning_tickets_marker(
             %Header{
               timeslot: header_timeslot,
               winning_tickets_marker: winning_tickets_marker
             },
             state_timeslot,
             %Safrole{ticket_accumulator: gamma_a}
           ) do
    {new_epoch_index, new_epoch_phase} = Time.epoch_index_and_phase(header_timeslot)
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
