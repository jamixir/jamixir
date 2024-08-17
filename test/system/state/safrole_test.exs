defmodule System.State.SafroleTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias System.State.{Safrole, SealKeyTicket}

  describe "outside_in_sequencer/1" do
    test "reorders an empty list" do
      assert Safrole.outside_in_sequencer([]) == []
    end

    test "reorders a list with a single element" do
      ticket = build(:seal_key_ticket)
      assert Safrole.outside_in_sequencer([ticket]) == [ticket]
    end

    test "reorders a list with two elements" do
      tickets = build_list(2, :seal_key_ticket)

      assert Safrole.outside_in_sequencer(tickets) == tickets
    end

    test "reorders a list with three elements" do
      [t1, t2, t3] = build_list(3, :seal_key_ticket)

      assert Safrole.outside_in_sequencer([t1, t2, t3]) == [t1, t3, t2]
    end

    test "reorders a list with four elements" do
      [t1, t2, t3, t4] = build_list(4, :seal_key_ticket)

      assert Safrole.outside_in_sequencer([t1, t2, t3, t4]) == [t1, t4, t2, t3]
    end

    test "reorders a list with five elements" do
      [t1, t2, t3, t4, t5] = build_list(5, :seal_key_ticket)

      assert Safrole.outside_in_sequencer([t1, t2, t3, t4, t5]) == [t1, t5, t2, t4, t3]
    end
  end
end
