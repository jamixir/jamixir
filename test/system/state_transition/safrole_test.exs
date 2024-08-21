defmodule System.StateTransition.SafroleStateTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias System.State
  alias Block.{Header}
  alias Block
  alias System.State.{Safrole, Judgements}
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
      build(:genesis_state)
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

  describe "encode/1" do
    test "encode smoke test" do
      Codec.Encoder.encode(build(:safrole))
    end
  end
end
