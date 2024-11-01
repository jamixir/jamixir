defmodule System.State.SafroleTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias System.State.EntropyPool
  alias System.State.Safrole
  alias Util.Hash

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

  describe "generate_index_using_entropy/3" do
    test "uses default validator set size" do
      entropy = Hash.random()
      index = Safrole.generate_index_using_entropy(entropy, 5)

      assert index >= 0 and index < Constants.validator_count()
    end

    test "returns a value within the valid range for validator set size" do
      entropy = Hash.random()
      validator_set_size = 10

      for i <- 0..100 do
        index = Safrole.generate_index_using_entropy(entropy, i, validator_set_size)
        assert index >= 0 and index < validator_set_size
      end
    end

    test "returns consistent results for the same entropy and index" do
      entropy = Hash.random()
      validator_set_size = 100
      index = Safrole.generate_index_using_entropy(entropy, 5, validator_set_size)

      # Re-run with the same entropy and index
      index_repeated = Safrole.generate_index_using_entropy(entropy, 5, validator_set_size)

      assert index == index_repeated
    end

    test "handles the case when validator_set_size is 1" do
      entropy = Hash.random()
      validator_set_size = 1

      for i <- 0..100 do
        index = Safrole.generate_index_using_entropy(entropy, i, validator_set_size)
        assert index == 0
      end
    end
  end

  describe "get_epoch_slot_sealers_/5" do
    setup do
      safrole = build(:safrole)
      entropy_pool = build(:entropy_pool)
      validators = build_list(4, :validator)

      %{safrole: safrole, entropy_pool: entropy_pool, validators: validators}
    end

    test "same epoch index, returns current_epoch_slot_sealers", %{safrole: safrole} do
      header = build(:header, timeslot: 2)
      timeslot = 1

      result =
        Safrole.get_epoch_slot_sealers_(header, timeslot, safrole, %EntropyPool{}, nil)

      assert result == safrole.current_epoch_slot_sealers
    end

    test "epoch advances, submission ended, accumulator full, reorders sealers", %{
      safrole: safrole
    } do
      safrole = %{
        safrole
        | current_epoch_slot_sealers: build_list(600, :seal_key_ticket),
          ticket_accumulator: build_list(600, :seal_key_ticket)
      }

      header = build(:header, timeslot: 600)
      timeslot = 599

      result =
        Safrole.get_epoch_slot_sealers_(header, timeslot, safrole, %EntropyPool{}, nil)

      expected_result = Safrole.outside_in_sequencer(safrole.ticket_accumulator)
      assert result == expected_result
    end

    test "fallback case: uses fallback_key_sequence", %{
      safrole: safrole,
      entropy_pool: entropy_pool,
      validators: validators
    } do
      safrole = %{
        safrole
        | current_epoch_slot_sealers: build_list(600, :seal_key_ticket)
      }

      header = build(:header, timeslot: 600)
      timeslot = 400

      result =
        Safrole.get_epoch_slot_sealers_(
          header,
          timeslot,
          safrole,
          entropy_pool,
          validators
        )

      expected_result = Safrole.fallback_key_sequence(entropy_pool.n2, validators)
      assert result == expected_result
    end

    test "handles empty current_epoch_slot_sealers", %{
      safrole: safrole,
      entropy_pool: entropy_pool,
      validators: validators
    } do
      safrole = %{safrole | current_epoch_slot_sealers: []}
      header = build(:header, timeslot: 600)

      result =
        Safrole.get_epoch_slot_sealers_(header, 400, safrole, entropy_pool, validators)

      expected_result = Safrole.fallback_key_sequence(entropy_pool.n2, validators)
      assert result == expected_result
    end
  end

  describe "encode/1" do
    test "encodes a safrole smoke test" do
      safrole = build(:safrole)
      Encodable.encode(safrole)
    end

    test "encode with seal type 1" do
      safrole =
        build(:safrole,
          pending: [],
          epoch_root: <<0>>,
          current_epoch_slot_sealers: [<<2>>],
          ticket_accumulator: []
        )

      assert Encodable.encode(safrole) == "\0\x01\x02\0"
    end
  end
end
