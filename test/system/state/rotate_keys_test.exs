defmodule System.State.RotateKeysTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block.Header
  alias System.State.{Judgements, RotateKeys, Safrole}
  alias TestHelper, as: TH
  alias Types

  setup do
    [validator1, validator2, validator3] = build_list(3, :validator)

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

      {new_pending, new_current, new_prev, new_epoch_root} =
        RotateKeys.rotate_keys(header, timeslot, [], [v2], [v1, v2, v3], safrole, %Judgements{
          punish: offenders
        })

      assert Enum.all?(new_pending, &TH.nullified?/1)
      assert new_current == safrole.pending
      assert new_prev == [v2]
      assert byte_size(new_epoch_root) == 144
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

      {new_pending, new_current, new_prev, new_epoch_root} =
        RotateKeys.rotate_keys(header, timeslot, [], [v2], [v1, v2, v3], safrole, %Judgements{
          punish: offenders
        })

      assert new_pending == [v1, v2, v3]
      assert new_current == safrole.pending
      assert new_prev == [v2]
      assert byte_size(new_epoch_root) == 144
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

      {new_pending, new_current, new_prev, new_epoch_root} =
        RotateKeys.rotate_keys(header, timeslot, [], [v2], [v1, v2, v3], safrole, %Judgements{
          punish: offenders
        })

      assert Enum.count(new_pending, &TH.nullified?/1) == 2
      assert Enum.at(new_pending, 1) == v2
      assert new_current == safrole.pending
      assert new_prev == [v2]
      assert byte_size(new_epoch_root) == 144
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
  end
end
