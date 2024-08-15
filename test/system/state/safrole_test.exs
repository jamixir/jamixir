defmodule System.State.SafroleTest do
  use ExUnit.Case
  alias System.State.{Safrole, Ticket}

  describe "outside_in_sequencer/1" do
    test "reorders an empty list" do
      assert Safrole.outside_in_sequencer([]) == []
    end

    test "reorders a list with a single element" do
      ticket = %Ticket{id: <<1::256>>, attempt: 1}
      assert Safrole.outside_in_sequencer([ticket]) == [ticket]
    end

    test "reorders a list with two elements" do
      ticket1 = %Ticket{id: <<1::256>>, attempt: 1}
      ticket2 = %Ticket{id: <<2::256>>, attempt: 2}

      assert Safrole.outside_in_sequencer([ticket1, ticket2]) == [ticket1, ticket2]
    end

    test "reorders a list with three elements" do
      ticket1 = %Ticket{id: <<1::256>>, attempt: 1}
      ticket2 = %Ticket{id: <<2::256>>, attempt: 2}
      ticket3 = %Ticket{id: <<3::256>>, attempt: 3}

      assert Safrole.outside_in_sequencer([ticket1, ticket2, ticket3]) == [
               ticket1,
               ticket3,
               ticket2
             ]
    end

    test "reorders a list with four elements" do
      ticket1 = %Ticket{id: <<1::256>>, attempt: 1}
      ticket2 = %Ticket{id: <<2::256>>, attempt: 2}
      ticket3 = %Ticket{id: <<3::256>>, attempt: 3}
      ticket4 = %Ticket{id: <<4::256>>, attempt: 4}

      assert Safrole.outside_in_sequencer([ticket1, ticket2, ticket3, ticket4]) == [
               ticket1,
               ticket4,
               ticket2,
               ticket3
             ]
    end

    test "reorders a list with five elements" do
      ticket1 = %Ticket{id: <<1::256>>, attempt: 1}
      ticket2 = %Ticket{id: <<2::256>>, attempt: 2}
      ticket3 = %Ticket{id: <<3::256>>, attempt: 3}
      ticket4 = %Ticket{id: <<4::256>>, attempt: 4}
      ticket5 = %Ticket{id: <<5::256>>, attempt: 5}

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
