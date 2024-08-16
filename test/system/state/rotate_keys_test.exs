defmodule System.State.RotateKeysTest do
  use ExUnit.Case
  alias System.State.{RotateKeys, Safrole, Judgements}
  alias Types
  alias Block.Header
  alias TestHelper, as: TH

  setup do
    next_validators = Enum.map(1..3, &TH.create_validator/1)
    offenders = MapSet.new([<<1::256>>, <<3::256>>])

    {:ok, next_validators: next_validators, offenders: offenders}
  end

  describe "nullify_offenders/2" do
    test "nullifies validators that are in the offenders set", %{
      next_validators: next_validators,
      offenders: offenders
    } do
      result = RotateKeys.nullify_offenders(next_validators, offenders)

      # Validator 1 and 3 are nullified, 2 is not

      assert TH.is_nullified(Enum.at(result, 0))
      assert Enum.at(result, 1) == Enum.at(next_validators, 1)
      assert TH.is_nullified(Enum.at(result, 2))
    end

    test "returns the same validators if none are in the offenders set", %{
      next_validators: next_validators
    } do
      # No matching offenders
      offenders = MapSet.new([<<4::256>>])

      result = RotateKeys.nullify_offenders(next_validators, offenders)

      assert result == next_validators
    end

    test "handles an empty offenders set", %{
      next_validators: next_validators
    } do
      # No matching offenders
      offenders = MapSet.new()

      result = RotateKeys.nullify_offenders(next_validators, offenders)

      assert result == next_validators
    end
  end

  setup do
    [validator1, validator2, validator3] = Enum.map(1..3, fn _ -> TH.random_validator() end)

    header = %Header{timeslot: 600}
    timeslot = 0
    safrole = %Safrole{pending: [validator2], epoch_root: :crypto.strong_rand_bytes(144)}

    {:ok,
     validator1: validator1,
     validator2: validator2,
     validator3: validator3,
     header: header,
     timeslot: timeslot,
     safrole: safrole}
  end

  describe "rotate_keys/7" do
    test "New epoch, all of the next validators are in the offenders set => new pending is empty",
         %{
           validator1: v1,
           validator2: v2,
           validator3: v3,
           header: header,
           timeslot: timeslot,
           safrole: safrole
         } do
      offenders = MapSet.new([v1.ed25519, v2.ed25519, v3.ed25519])

      {new_pending, new_current, new_prev, _new_epoch_root} =
        RotateKeys.rotate_keys(header, timeslot, [], [v2], [v1, v2, v3], safrole, %Judgements{
          punish: offenders
        })

      assert Enum.all?(new_pending, &TH.is_nullified/1)
      assert new_current == safrole.pending
      assert new_prev == [v2]
    end

    test "New epoch, no validators nullified", %{
      validator1: v1,
      validator2: v2,
      validator3: v3,
      header: header,
      timeslot: timeslot,
      safrole: safrole
    } do
      offenders = MapSet.new()

      {new_pending, new_current, new_prev, _new_epoch_root} =
        RotateKeys.rotate_keys(header, timeslot, [], [v2], [v1, v2, v3], safrole, %Judgements{
          punish: offenders
        })

      assert new_pending == [v1, v2, v3]
      assert new_current == safrole.pending
      assert new_prev == [v2]
    end

    test "New epoch, some validators nullified", %{
      validator1: v1,
      validator2: v2,
      validator3: v3,
      header: header,
      timeslot: timeslot,
      safrole: safrole
    } do
      offenders = MapSet.new([v1.ed25519, v3.ed25519])

      {new_pending, new_current, new_prev, _new_epoch_root} =
        RotateKeys.rotate_keys(header, timeslot, [], [v2], [v1, v2, v3], safrole, %Judgements{
          punish: offenders
        })

      assert Enum.count(new_pending, &TH.is_nullified/1) == 2
      assert Enum.at(new_pending, 1) == v2
      assert new_current == safrole.pending
      assert new_prev == [v2]
    end

    test "No new epoch, state unchanged", %{
      validator2: v2,
      safrole: safrole
    } do
      result =
        RotateKeys.rotate_keys(
          %Header{timeslot: 3},
          2,
          [],
          [v2],
          [],
          safrole,
          %Judgements{punish: MapSet.new()}
        )

      assert result == {safrole.pending, [v2], [], safrole.epoch_root}
    end

    test "Error during epoch determination raises exception", %{validator2: v2, safrole: safrole} do
      assert_raise RuntimeError, fn ->
        RotateKeys.rotate_keys(
          %Header{timeslot: 10},
          20,
          [],
          [v2],
          [],
          safrole,
          %Judgements{punish: MapSet.new()}
        )
      end
    end
  end
end
