defmodule System.State.RotateKeysTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block.Header
  alias System.State
  alias System.State.{Judgements, RotateKeys, Safrole}
  alias TestHelper, as: TH
  alias Types

  setup do
    [validator1, validator2, validator3] = build_list(3, :validator)

    state = %State{
      timeslot: 0,
      prev_validators: [],
      curr_validators: [validator2],
      next_validators: [validator1, validator2, validator3],
      safrole: %Safrole{pending: [validator2], epoch_root: :crypto.strong_rand_bytes(144)}
    }

    {:ok,
     validator1: validator1,
     validator2: validator2,
     validator3: validator3,
     header: %Header{timeslot: 600},
     state: state}
  end

  describe "rotate_keys/3" do
    test "New epoch, all of the next validators are in the offenders set => new pending is empty",
         %{
           validator1: v1,
           validator2: v2,
           validator3: v3,
           header: header,
           state: state
         } do
      offenders = MapSet.new([v1.ed25519, v2.ed25519, v3.ed25519])

      {pending_, current_, prev_, epoch_root_} =
        RotateKeys.rotate_keys(header, state, %Judgements{offenders: offenders})

      assert Enum.all?(pending_, &TH.nullified?/1)
      assert current_ == state.safrole.pending
      assert prev_ == [v2]
      assert byte_size(epoch_root_) == 144
    end

    test "New epoch, no validators nullified", %{
      validator1: v1,
      validator2: v2,
      validator3: v3,
      header: header,
      state: state
    } do
      offenders = MapSet.new()

      {pending_, current_, prev_, epoch_root_} =
        RotateKeys.rotate_keys(header, state, %Judgements{offenders: offenders})

      assert pending_ == [v1, v2, v3]
      assert current_ == state.safrole.pending
      assert prev_ == [v2]
      assert byte_size(epoch_root_) == 144
    end

    test "New epoch, some validators nullified", %{
      validator1: v1,
      validator2: v2,
      validator3: v3,
      header: header,
      state: state
    } do
      offenders = MapSet.new([v1.ed25519, v3.ed25519])

      {pending_, current_, prev_, epoch_root_} =
        RotateKeys.rotate_keys(header, state, %Judgements{offenders: offenders})

      assert Enum.count(pending_, &TH.nullified?/1) == 2
      assert Enum.at(pending_, 1) == v2
      assert current_ == state.safrole.pending
      assert prev_ == [v2]
      assert byte_size(epoch_root_) == 144
    end

    test "No new epoch, state unchanged", %{validator2: v2, state: state} do
      state = %State{state | timeslot: 2, next_validators: []}

      result =
        RotateKeys.rotate_keys(%Header{timeslot: 3}, state, %Judgements{offenders: MapSet.new()})

      assert result == {state.safrole.pending, [v2], [], state.safrole.epoch_root}
    end
  end
end
