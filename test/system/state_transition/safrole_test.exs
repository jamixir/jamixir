defmodule System.StateTransition.SafroleStateTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias System.State
  alias Block.{Header}
  alias Block
  alias System.State.{Safrole, Judgements, Safrole}
  alias TestHelper, as: TH

  def genesis_state() do
    case Process.get(:memoized_genesis_state) do
      nil ->
        state = build(:genesis_state_with_safrole)
        Process.put(:memoized_genesis_state, state)
        state

      state ->
        state
    end
  end

  describe "safrole state update on new epoch with some validators nullified" do
    setup do
      %{state: state, validators: validators, key_pairs: key_pairs} = genesis_state()

      state = %{
        state
        | judgements: %Judgements{
            punish:
              MapSet.new([
                Enum.at(validators, 0).ed25519,
                Enum.at(validators, 2).ed25519
              ])
          },
          timeslot: 599
      }

      # Sign the header with the appropriate key_pair (validator2 is the current validator)
      header =
        System.HeaderSeal.seal_header(
          %Header{timeslot: 600, block_author_key_index: 0},
          state.safrole.current_epoch_slot_sealers,
          state.entropy_pool,
          Enum.at(key_pairs, 0)
        )

      {:ok, state: state, header: header, validator2: Enum.at(validators, 1)}
    end

    @tag :slow
    test "correctly updates safrole state", %{
      state: state,
      header: header,
      validator2: validator2
    } do
      block = %Block{header: header, extrinsic: %Block.Extrinsic{}}

      new_state = State.add_block(state, block)

      # first and third validators are nullified
      assert TH.nullified?(Enum.at(new_state.safrole.pending, 0))
      assert TH.nullified?(Enum.at(new_state.safrole.pending, 2))
      # second validator is not nullified
      assert Enum.at(new_state.safrole.pending, 1) == validator2

      # nothing better to test until vrf is implemented
      assert new_state.safrole.epoch_root != state.safrole.epoch_root
    end
  end

  describe "updates state.safrole.current_epoch_slot_sealers" do
    setup do
      %{state: state, validators: validators, key_pairs: key_pairs} = genesis_state()

      state = %{
        state
        | curr_validators: validators,
          prev_validators: [],
          next_validators: validators,
          timeslot: 500
      }

      block_author_key_index = rem(501, length(validators))

      header =
        System.HeaderSeal.seal_header(
          %Header{timeslot: 501, block_author_key_index: block_author_key_index},
          state.safrole.current_epoch_slot_sealers,
          state.entropy_pool,
          Enum.at(key_pairs, block_author_key_index)
        )

      block = %Block{header: header, extrinsic: %Block.Extrinsic{}}
      {:ok, state: state, block: block, header: header, key_pairs: key_pairs}
    end

    @tag :slow
    test "maintains current_epoch_slot_sealers when epoch does not advance", %{
      state: state,
      block: block
    } do
      new_state = State.add_block(state, block)

      assert new_state.safrole.current_epoch_slot_sealers ==
               state.safrole.current_epoch_slot_sealers
    end

    @tag :slow
    test "reorders current_epoch_slot_sealers when epoch advances and submission ends", %{
      state: state,
      block: block,
      header: header,
      key_pairs: key_pairs
    } do
      # Simulate the expected outcome of rotate_keys (new_current = pending)
      expected_current_validators = state.safrole.pending

      # Simulate the expected outcome of get_posterior_epoch_slot_sealers
      expected_sealers = Safrole.outside_in_sequencer(state.safrole.current_epoch_slot_sealers)

      # because of the outside in sequencer
      # i am not sure how in actuall runtime the block author is supposed to know that
      # assuming we will find out when doing #99
      block_auth_index = length(key_pairs) - 1

      # Seal the header with the expected outcomes
      header =
        System.HeaderSeal.seal_header(
          %{header | timeslot: 601, block_author_key_index: block_auth_index},
          expected_sealers,
          state.entropy_pool,
          Enum.at(key_pairs, block_auth_index)
        )

      block = %{block | header: header}

      # Call add_block
      new_state = State.add_block(state, block)

      # Assertions
      assert new_state.safrole.current_epoch_slot_sealers == expected_sealers
      assert new_state.curr_validators == expected_current_validators
    end

    @tag :slow
    test "replaces current_epoch_slot_sealers when fallback_key_sequence is used", %{} do
      %{state: state, key_pairs: key_pairs} = genesis_state()

      state = %{state | timeslot: 499}
      header = build(:header, timeslot: 600)

      new_entropy_pool =
        System.State.EntropyPool.rotate_history(
          header,
          state.timeslot,
          state.entropy_pool
        )

      {_, new_curr_validators, _, _} =
        System.State.RotateKeys.rotate_keys(
          header,
          state.timeslot,
          state.prev_validators,
          state.curr_validators,
          state.next_validators,
          state.safrole,
          state.judgements
        )

      posterior_epoch_slot_sealers =
        System.State.Safrole.get_posterior_epoch_slot_sealers(
          header,
          state.timeslot,
          state.safrole,
          new_entropy_pool,
          new_curr_validators
        )

      # find the index in new_curr_validators
      # such that new_curr_validators[index].bandersnatch = posterior_epoch_slot_sealers[0]
      block_auth_index =
        Enum.find_index(
          new_curr_validators,
          &(&1.bandersnatch == Enum.at(posterior_epoch_slot_sealers, 0))
        )

      header =
        System.HeaderSeal.seal_header(
          %{header | block_author_key_index: block_auth_index},
          posterior_epoch_slot_sealers,
          state.entropy_pool,
          Enum.at(key_pairs, block_auth_index)
        )

      expected_current_validators = state.safrole.pending

      # Simulate the expected outcome of get_posterior_epoch_slot_sealers
      expected_sealers =
        Safrole.fallback_key_sequence(new_entropy_pool.n2, expected_current_validators)

      block = build(:block, header: header)
      new_state = State.add_block(state, block)
      assert new_state.safrole.current_epoch_slot_sealers == expected_sealers
      assert new_state.curr_validators == expected_current_validators
    end
  end

  describe "encode/1" do
    test "encode smoke test" do
      Codec.Encoder.encode(build(:safrole))
    end
  end
end
