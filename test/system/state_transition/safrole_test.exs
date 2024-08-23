defmodule System.StateTransition.SafroleStateTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias System.State
  alias Block.{Header}
  alias Block
  alias System.State.{Safrole, Judgements, Safrole}
  alias TestHelper, as: TH

  setup do
    [validator1, validator2, validator3] = Enum.map(1..3, &TH.create_validator/1)
    offenders = MapSet.new([validator1.ed25519, validator3.ed25519])

    # Initial state
    safrole = %Safrole{
      pending: [validator2],
      epoch_root: <<0xABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890::256>>
    }

    judgements = %Judgements{punish: offenders}

    state = %System.State{
      build(:advanced_state)
      | curr_validators: [validator2],
        prev_validators: [],
        next_validators: [validator1, validator2, validator3],
        safrole: safrole,
        judgements: judgements,
        timeslot: 599
    }

    # New epoch
    header = %Header{timeslot: 600}

    {:ok, state: state, header: header, validator2: validator2}
  end

  describe "safrole state update on new epoch with some validators nullified" do
    test "correctly updates safrole state", %{
      state: state,
      header: header,
      validator2: validator2
    } do
      block = %Block{header: header, extrinsic: %Block.Extrinsic{}}

      new_state = State.add_block(state, block)

      # first and third validators are nullified
      assert TH.is_nullified(Enum.at(new_state.safrole.pending, 0))
      assert TH.is_nullified(Enum.at(new_state.safrole.pending, 2))
      # second validator is not nullified
      assert Enum.at(new_state.safrole.pending, 1) == validator2

      # nothing better to test until vrf is implemented
      assert new_state.safrole.epoch_root != state.safrole.epoch_root
    end
  end

  describe "updates state.safrole.current_epoch_slot_sealers" do
    setup do
      # Create the necessary initial state
      safrole = build(:safrole)
      validators = build_list(3, :random_validator)

      state = %System.State{
        build(:advanced_state)
        | curr_validators: validators,
          prev_validators: [],
          next_validators: validators,
          safrole: safrole,
          timeslot: 400
      }

      header = build(:header, timeslot: 401)
      block = %Block{header: header, extrinsic: %Block.Extrinsic{}}
      {:ok, state: state, block: block, header: header}
    end

    test "maintains current_epoch_slot_sealers when epoch does not advance", %{
      state: s,
      block: b
    } do
      new_state = State.add_block(s, b)

      assert new_state.safrole.current_epoch_slot_sealers ==
               s.safrole.current_epoch_slot_sealers
    end

    test "reorders current_epoch_slot_sealers when epoch advances and submission ends", %{
      state: s,
      block: b,
      header: h
    } do
      # Ensure ticket accumulator is full
      safrole = %{
        s.safrole
        | current_epoch_slot_sealers: build_list(600, :seal_key_ticket),
          ticket_accumulator: build_list(600, :seal_key_ticket)
      }

      state = %{s | safrole: safrole, timeslot: 501}

      block = %{b | header: %Header{h | timeslot: 601}}
      new_state = State.add_block(state, block)

      expected_sealers = Safrole.outside_in_sequencer(safrole.current_epoch_slot_sealers)
      assert new_state.safrole.current_epoch_slot_sealers == expected_sealers
    end

    test "replaces current_epoch_slot_sealers when fallback_key_sequence is used", %{
      state: s,
      block: b,
      header: h
    } do
      # Set up state to trigger fallback_key_sequence
      safrole = %{
        s.safrole
        | current_epoch_slot_sealers: build_list(600, :seal_key_ticket)
      }

      state = %{s | safrole: safrole, timeslot: 499}

      block = %{b | header: %Header{h | timeslot: 601}}
      new_state = State.add_block(state, block)

      # epoch was changed therefore new_state.curr_validators == safrole.pending
      expected_sealers = Safrole.fallback_key_sequence(new_state.entropy_pool, safrole.pending)
      assert new_state.safrole.current_epoch_slot_sealers == expected_sealers
    end
  end

  describe "encode/1" do
    test "encode smoke test" do
      Codec.Encoder.encode(build(:safrole))
    end
  end
end
