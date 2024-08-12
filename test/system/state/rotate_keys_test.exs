defmodule System.State.RotateKeysTest do
  use ExUnit.Case
  alias System.State.{RotateKeys, Validator, Safrole, Judgements}
  alias Types
  alias Block.Header

  defp is_nullified(%Validator{} = validator) do
    validator.bandersnatch == <<0::256>> and
      validator.ed25519 == <<0::256>> and
      validator.bls == <<0::1152>> and
      validator.metadata == <<0::1024>>
  end

  setup do
    validator1 = %Validator{
      bandersnatch: <<1::256>>,
      ed25519: <<1::256>>,
      bls: <<1::1152>>,
      metadata: <<1::1024>>
    }

    validator2 = %Validator{
      bandersnatch: <<2::256>>,
      ed25519: <<2::256>>,
      bls: <<2::1152>>,
      metadata: <<2::1024>>
    }

    validator3 = %Validator{
      bandersnatch: <<3::256>>,
      ed25519: <<3::256>>,
      bls: <<3::1152>>,
      metadata: <<3::1024>>
    }

    next_validators = [validator1, validator2, validator3]

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

      assert is_nullified(Enum.at(result, 0))
      assert Enum.at(result, 1) == Enum.at(next_validators, 1)
      assert is_nullified(Enum.at(result, 2))
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
    validator1 = %Validator{
      bandersnatch: :crypto.strong_rand_bytes(32),
      ed25519: :crypto.strong_rand_bytes(32),
      bls: :crypto.strong_rand_bytes(144),
      metadata: :crypto.strong_rand_bytes(128)
    }

    validator2 = %Validator{
      bandersnatch: :crypto.strong_rand_bytes(32),
      ed25519: :crypto.strong_rand_bytes(32),
      bls: :crypto.strong_rand_bytes(144),
      metadata: :crypto.strong_rand_bytes(128)
    }

    validator3 = %Validator{
      bandersnatch: :crypto.strong_rand_bytes(32),
      ed25519: :crypto.strong_rand_bytes(32),
      bls: :crypto.strong_rand_bytes(144),
      metadata: :crypto.strong_rand_bytes(128)
    }

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

      assert Enum.all?(new_pending, &is_nullified/1)
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

      assert Enum.count(new_pending, &is_nullified/1) == 2
      assert Enum.at(new_pending, 1) == v2
      assert new_current == safrole.pending
      assert new_prev == [v2]
    end

    test "No new epoch, state unchanged", %{
      validator2: v2,
      header: header,
      timeslot: timeslot,
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
