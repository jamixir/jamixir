defmodule Block.Extrinsic.GuarantorAssignmentsTest do
  alias Block.Extrinsic.GuarantorAssignments
  alias System.State.Validator
  alias Util.Hash
  import Jamixir.Factory
  use ExUnit.Case

  describe "rotate/2" do
    test "rotate empty list" do
      assert GuarantorAssignments.rotate([], 10) == []
    end

    test "rotate elements" do
      assert GuarantorAssignments.rotate([1, 2, 3], 10) == [1, 0, 1]
      assert GuarantorAssignments.rotate([300, 340, 1], 50) == [0, 0, 1]
    end
  end

  describe "permute/2" do
    test "permute when e is a list" do
      p1 = GuarantorAssignments.permute(1..1100 |> Enum.to_list(), 3)
      p2 = GuarantorAssignments.permute(1..1100 |> Enum.to_list(), 4)

      assert p1 == [0, 0, 1, 1, 1, 0]
      assert p2 == [1, 1, 0, 0, 0, 1]

      assert {length(p1), length(p2)} ==
               {Constants.validator_count(), Constants.validator_count()}
    end

    test "permute when e is a hash" do
      h1 =
        JsonDecoder.from_json(
          "0x11da6d1f761ddf9bdb4c9d6e5303ebd41f61858d0a5647a1a7bfe089bf921be9"
        )

      h2 =
        JsonDecoder.from_json(
          "0xe12c22d4f162d9a012c9319233da5d3e923cc5e1029b8f90e47249c9ab256b35"
        )

      p1 = GuarantorAssignments.permute(h1, 2)
      p2 = GuarantorAssignments.permute(h2, 14)
      assert p1 !== p2

      assert {length(p1), length(p2)} ==
               {Constants.validator_count(), Constants.validator_count()}
    end
  end

  describe "guarantors/4" do
    test "guarantors smoke test" do
      validators = build_list(Constants.validator_count(), :validator)

      %GuarantorAssignments{assigned_cores: indexes, validators: keys} =
        GuarantorAssignments.guarantors(Hash.random(), 2, validators, MapSet.new())

      assert length(indexes) == Constants.validator_count()
      assert MapSet.difference(MapSet.new(validators), MapSet.new(keys)) == MapSet.new([])

      assert indexes |> Enum.sort() ==
               0..(Constants.core_count() - 1) |> Enum.flat_map(&[&1, &1, &1])
    end

    test "guarantors nullify offender" do
      [v1 | other] = build_list(3, :validator)

      %GuarantorAssignments{validators: [key1 | _]} =
        GuarantorAssignments.guarantors(
          Hash.random(),
          2,
          [v1 | other],
          MapSet.new([v1.ed25519])
        )

      assert key1 == Validator.nullified(v1)
    end
  end

  describe "prev_guarantors/6" do
    test "prev_guarantors previous rotation false" do
      {n2, n3} = {Hash.random(), Hash.random()}
      k = build_list(2, :validator)
      p = build_list(2, :validator)
      o = MapSet.new()

      assert GuarantorAssignments.prev_guarantors(n2, n3, 100, k, p, o) ==
               GuarantorAssignments.guarantors(n2, 100 - Constants.rotation_period(), k, o)
    end

    test "prev_guarantors previous rotation true" do
      {n2, n3} = {Hash.random(), Hash.random()}
      k = build_list(2, :validator)
      p = build_list(2, :validator)
      o = MapSet.new()

      assert GuarantorAssignments.prev_guarantors(n2, n3, 13, k, p, o) ==
               GuarantorAssignments.guarantors(n3, 13 - Constants.rotation_period(), p, o)
    end
  end
end
