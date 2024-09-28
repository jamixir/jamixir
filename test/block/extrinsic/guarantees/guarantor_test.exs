defmodule Block.Extrinsic.GuarantorTest do
  alias Block.Extrinsic.Guarantor
  alias System.State.Validator
  alias Util.Hash
  import Jamixir.Factory
  use ExUnit.Case

  describe "rotate/2" do
    test "rotate empty list" do
      assert Guarantor.rotate([], 10) == []
    end

    test "rotate elements" do
      assert Guarantor.rotate([1, 2, 3], 10) == [11, 12, 13]
      assert Guarantor.rotate([300, 340, 1], 50) == [9, 49, 51]
    end
  end

  describe "permute/2" do
    test "permute when e is a list" do
      p1 = Guarantor.permute(1..1100 |> Enum.to_list(), 2)
      p2 = Guarantor.permute(1..1100 |> Enum.to_list(), 700)
      assert p1 !== p2

      assert p1 |> Enum.take(10) == [0, 1, 1, 2, 3, 3, 4, 5, 5, 6]
      assert p2 |> Enum.take(10) == [10, 11, 11, 12, 13, 13, 14, 15, 15, 16]

      assert {length(p1), length(p2)} ==
               {Constants.validator_count(), Constants.validator_count()}
    end

    test "permute when e is a hash" do
      p1 = Guarantor.permute(Hash.random(), 2)
      p2 = Guarantor.permute(Hash.random(), 500)
      assert p1 !== p2

      assert {length(p1), length(p2)} ==
               {Constants.validator_count(), Constants.validator_count()}
    end
  end

  describe "guarantors/4" do
    test "guarantors smoke test" do
      validators = build_list(Constants.validator_count(), :validator)

      %Guarantor{assigned_cores: indexes, validators: keys} =
        Guarantor.guarantors(Hash.random(), 2, validators, MapSet.new())

      assert length(indexes) == Constants.validator_count()
      assert MapSet.difference(MapSet.new(validators), MapSet.new(keys)) == MapSet.new([])

      assert indexes |> Enum.sort() ==
               0..(Constants.core_count() - 1) |> Enum.flat_map(&[&1, &1, &1])
    end

    test "guarantors nullify offender" do
      [v1 | other] = build_list(3, :validator)

      %Guarantor{validators: [key1 | _]} =
        Guarantor.guarantors(
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

      assert Guarantor.prev_guarantors(n2, n3, 100, k, p, o) ==
               Guarantor.guarantors(n2, 100 - Constants.rotation_period(), k, o)
    end

    test "prev_guarantors previous rotation true" do
      {n2, n3} = {Hash.random(), Hash.random()}
      k = build_list(2, :validator)
      p = build_list(2, :validator)
      o = MapSet.new()

      assert Guarantor.prev_guarantors(n2, n3, 605, k, p, o) ==
               Guarantor.guarantors(n3, 605 - Constants.rotation_period(), p, o)
    end
  end
end
