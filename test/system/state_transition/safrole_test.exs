defmodule System.StateTransition.SafroleStateTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias System.State
  alias Block.Header
  alias Block
  alias System.State.{EntropyPool, Judgements, RotateKeys, Safrole}
  alias TestHelper, as: TH
  import Mox
  setup :verify_on_exit!

  def genesis_state do
    case Process.get(:memoized_genesis_state) do
      nil ->
        state = build(:genesis_state_with_safrole)
        Process.put(:memoized_genesis_state, state)
        state

      state ->
        state
    end
  end

  setup_all do
    # Exclude Safrole module from being mocked
    Application.put_env(:jamixir, :original_modules, [System.State.Safrole])

    on_exit(fn ->
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  describe "safrole state update on new epoch with some validators nullified" do
    setup do
      %{state: state, validators: validators, key_pairs: key_pairs} = genesis_state()

      state = %{
        state
        | judgements: %Judgements{
            offenders: MapSet.new([Enum.at(validators, 0).ed25519, Enum.at(validators, 2).ed25519])
          },
          timeslot: 11,
          curr_validators: validators,
          prev_validators: [],
          next_validators: validators
      }

      h = %Header{timeslot: 12}
      entropy_pool_ = EntropyPool.rotate(h, state.timeslot, state.entropy_pool)
      new_tickets = seal_key_ticket_factory(key_pairs, entropy_pool_)

      new_safrole = %{
        state.safrole
        | ticket_accumulator: new_tickets,
          slot_sealers: new_tickets
      }

      state = %{
        state
        | safrole: new_safrole
      }

      expected_sealers = Safrole.outside_in_sequencer(new_tickets)
      # Sign the header with the appropriate key_pair (validator2 is the current validator)
      header =
        System.HeaderSeal.seal_header(
          %{h | block_author_key_index: 0},
          expected_sealers,
          entropy_pool_,
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

      {:ok, state_} = State.add_block(state, block)

      # first and third validators are nullified
      assert TH.nullified?(Enum.at(state_.safrole.pending, 0))
      assert TH.nullified?(Enum.at(state_.safrole.pending, 2))
      # second validator is not nullified
      assert Enum.at(state_.safrole.pending, 1) == validator2

      # nothing better to test until vrf is implemented
      assert state_.safrole.epoch_root != state.safrole.epoch_root
    end
  end

  setup do
    :ok
  end

  describe "updates state.safrole.slot_sealers" do
    setup do
      %{state: state, validators: validators, key_pairs: key_pairs} = genesis_state()

      state = %{
        state
        | curr_validators: validators,
          prev_validators: [],
          next_validators: validators,
          timeslot: 10
      }

      block_author_key_index = rem(11, length(validators))

      h = %Header{timeslot: 11, block_author_key_index: block_author_key_index}
      entropy_pool_ = EntropyPool.rotate(h, state.timeslot, state.entropy_pool)

      header =
        System.HeaderSeal.seal_header(
          h,
          state.safrole.slot_sealers,
          entropy_pool_,
          Enum.at(key_pairs, block_author_key_index)
        )

      block = %Block{header: header, extrinsic: %Block.Extrinsic{}}
      {:ok, state: state, block: block, header: header, key_pairs: key_pairs}
    end

    @tag :slow
    test "maintains slot_sealers when epoch does not advance", %{
      state: state,
      block: block
    } do
      {:ok, state_} = State.add_block(state, block)

      assert state_.safrole.slot_sealers ==
               state.safrole.slot_sealers
    end

    @tag :slow
    test "reorders slot_sealers when epoch advances and submission ends", %{
      state: state,
      block: block,
      header: header,
      key_pairs: key_pairs
    } do
      # Simulate the expected outcome of rotate_keys (current_ = pending)
      expected_current_validators = state.safrole.pending

      # because of the outside in sequencer
      # i am not sure how in actuall runtime the block author is supposed to know that
      # assuming we will find out when doing #99
      block_auth_index = length(key_pairs) - 1
      header = %{header | timeslot: 13, block_author_key_index: block_auth_index}

      entropy_pool_ = EntropyPool.rotate(header, state.timeslot, state.entropy_pool)
      new_tickets = seal_key_ticket_factory(key_pairs, entropy_pool_)

      state = %{
        state
        | safrole: %{
            state.safrole
            | ticket_accumulator: new_tickets,
              slot_sealers: new_tickets
          }
      }

      # Simulate the expected outcome of get_epoch_slot_sealers_
      expected_sealers = Safrole.outside_in_sequencer(state.safrole.slot_sealers)

      # Seal the header with the expected outcomes
      header =
        System.HeaderSeal.seal_header(
          header,
          expected_sealers,
          entropy_pool_,
          Enum.at(key_pairs, block_auth_index)
        )

      # Call add_block
      {:ok, state_} = State.add_block(state, %{block | header: header})

      # Assertions
      assert state_.safrole.slot_sealers == expected_sealers
      assert state_.curr_validators == expected_current_validators
    end

    @tag :slow
    test "replaces slot_sealers when fallback_key_sequence is used", %{} do
      %{state: state, key_pairs: key_pairs} = genesis_state()

      state = %{state | timeslot: 499}
      header = build(:header, timeslot: 600)

      entropy_pool_ = EntropyPool.rotate(header, state.timeslot, state.entropy_pool)
      {_, curr_validators_, _, _} = RotateKeys.rotate_keys(header, state, state.judgements)

      epoch_slot_sealers_ =
        Safrole.get_epoch_slot_sealers_(
          header,
          state.timeslot,
          state.safrole,
          entropy_pool_,
          curr_validators_
        )

      # find the index in curr_validators_
      # such that curr_validators_[index].bandersnatch = epoch_slot_sealers_[0]
      block_auth_index =
        Enum.find_index(
          curr_validators_,
          &(&1.bandersnatch == Enum.at(epoch_slot_sealers_, 0))
        )

      header =
        System.HeaderSeal.seal_header(
          %{header | block_author_key_index: block_auth_index},
          epoch_slot_sealers_,
          entropy_pool_,
          Enum.at(key_pairs, block_auth_index)
        )

      expected_current_validators = state.safrole.pending

      # Simulate the expected outcome of get_epoch_slot_sealers_
      expected_sealers =
        Safrole.fallback_key_sequence(entropy_pool_.n2, expected_current_validators)

      {:ok, state_} = State.add_block(state, build(:block, header: header))
      assert state_.safrole.slot_sealers == expected_sealers
      assert state_.curr_validators == expected_current_validators
    end
  end

  describe "encode/1" do
    test "encode smoke test" do
      Codec.Encoder.encode(build(:safrole))
    end
  end
end
