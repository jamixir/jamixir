defmodule System.Validators.SafroleValidatorTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block.Header
  alias System.Validators.Safrole
  alias Util.Hash

  setup_all do
    safrole = build(:safrole)

    %{
      entropy_pool: build(:entropy_pool),
      safrole: safrole,
      bandersnatch_keys: Enum.map(safrole.pending, & &1.bandersnatch)
    }
  end

  describe "valid_epoch_marker/4" do
    test "returns :ok when it's a new epoch and epoch_marker is valid", ctx do
      header = %Header{timeslot: 600, epoch_mark: {ctx.entropy_pool.n1, ctx.bandersnatch_keys}}

      assert :ok ==
               Safrole.valid_epoch_marker(header, 599, ctx.entropy_pool.n1, ctx.safrole.pending)
    end

    test "returns :ok when it's not a new epoch and epoch_marker is nil", ctx do
      header = %Header{timeslot: 44, epoch_mark: nil}

      assert :ok ==
               Safrole.valid_epoch_marker(header, 1, ctx.entropy_pool.n1, ctx.safrole.pending)
    end

    test "returns error when it's a new epoch but epoch_marker is invalid", ctx do
      header = %Header{timeslot: 900, epoch_mark: {Hash.one(), ctx.bandersnatch_keys}}

      assert {:error, "Invalid epoch marker"} ==
               Safrole.valid_epoch_marker(header, 3, ctx.entropy_pool.n1, ctx.safrole.pending)
    end

    test "return error when it is not a new epoch and epoch_marker is not nil", ctx do
      header = %Header{timeslot: 44, epoch_mark: {ctx.entropy_pool.n1, ctx.bandersnatch_keys}}

      assert {:error, "Invalid epoch marker"} ==
               Safrole.valid_epoch_marker(header, 1, ctx.entropy_pool.n1, ctx.safrole.pending)
    end
  end

  describe "valid_winning_tickets_marker/3" do
    test "returns :ok when conditions are met and winning_tickets_marker is valid", ctx do
      header = %Header{
        timeslot: 501,
        winning_tickets_marker:
          System.State.Safrole.outside_in_sequencer(ctx.safrole.ticket_accumulator)
      }

      assert :ok == Safrole.valid_winning_tickets_marker(header, 50, ctx.safrole)
    end

    test "returns error when conditions are met but winning_tickets_marker is invalid", ctx do
      header = %Header{timeslot: 599, winning_tickets_marker: ctx.safrole.ticket_accumulator}

      assert {:error, "Invalid winning tickets marker"} ==
               Safrole.valid_winning_tickets_marker(header, 499, ctx.safrole)
    end

    test "returns :ok when conditions are not met and winning_tickets_marker is nil", ctx do
      header = %Header{timeslot: 401, winning_tickets_marker: nil}
      assert :ok == Safrole.valid_winning_tickets_marker(header, 400, ctx.safrole)
    end

    test "returns error when conditions are not met but winning_tickets_marker is not nil", ctx do
      header = %Header{timeslot: 50, winning_tickets_marker: [Hash.one()]}

      assert {:error, "Invalid winning tickets marker"} ==
               Safrole.valid_winning_tickets_marker(header, 49, ctx.safrole)
    end
  end
end
