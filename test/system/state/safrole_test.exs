defmodule System.State.SafroleTest do
  use ExUnit.Case
  alias System.State.{Safrole, SealKeyTicket}

  describe "outside_in_sequencer/1" do
    test "reorders an empty list" do
      assert Safrole.outside_in_sequencer([]) == []
    end

    test "reorders a list with a single element" do
      ticket = %SealKeyTicket{id: <<1::256>>, entry_index: 1}
      assert Safrole.outside_in_sequencer([ticket]) == [ticket]
    end

    test "reorders a list with two elements" do
      ticket1 = %SealKeyTicket{id: <<1::256>>, entry_index: 1}
      ticket2 = %SealKeyTicket{id: <<2::256>>, entry_index: 2}

      assert Safrole.outside_in_sequencer([ticket1, ticket2]) == [ticket1, ticket2]
    end

    test "reorders a list with three elements" do
      ticket1 = %SealKeyTicket{id: <<1::256>>, entry_index: 1}
      ticket2 = %SealKeyTicket{id: <<2::256>>, entry_index: 2}
      ticket3 = %SealKeyTicket{id: <<3::256>>, entry_index: 3}

      assert Safrole.outside_in_sequencer([ticket1, ticket2, ticket3]) == [
               ticket1,
               ticket3,
               ticket2
             ]
    end

    test "reorders a list with four elements" do
      ticket1 = %SealKeyTicket{id: <<1::256>>, entry_index: 1}
      ticket2 = %SealKeyTicket{id: <<2::256>>, entry_index: 2}
      ticket3 = %SealKeyTicket{id: <<3::256>>, entry_index: 3}
      ticket4 = %SealKeyTicket{id: <<4::256>>, entry_index: 4}

      assert Safrole.outside_in_sequencer([ticket1, ticket2, ticket3, ticket4]) == [
               ticket1,
               ticket4,
               ticket2,
               ticket3
             ]
    end

    test "reorders a list with five elements" do
      ticket1 = %SealKeyTicket{id: <<1::256>>, entry_index: 1}
      ticket2 = %SealKeyTicket{id: <<2::256>>, entry_index: 2}
      ticket3 = %SealKeyTicket{id: <<3::256>>, entry_index: 3}
      ticket4 = %SealKeyTicket{id: <<4::256>>, entry_index: 4}
      ticket5 = %SealKeyTicket{id: <<5::256>>, entry_index: 5}

      assert Safrole.outside_in_sequencer([ticket1, ticket2, ticket3, ticket4, ticket5]) == [
               ticket1,
               ticket5,
               ticket2,
               ticket4,
               ticket3
             ]
    end
  end
end
