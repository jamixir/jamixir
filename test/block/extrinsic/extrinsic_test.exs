defmodule Block.ExtrinsicTest do
  use ExUnit.Case

  alias Block.Extrinsic.{Guarantee, Guarantee.WorkReport}

  describe "guarantees/1" do
    test "returns :ok for valid guarantees" do
      assert Guarantee.validate([\
               %Guarantee{
                 work_report: %WorkReport{core_index: 1},
                 timeslot: 100,
                 credential: [{1, <<1::512>>}, {2, <<2::512>>}]
               },
               %Guarantee{
                 work_report: %WorkReport{core_index: 2},
                 timeslot: 100,
                 credential: [{1, <<3::512>>}, {2, <<4::512>>}, {3, <<5::512>>}]
               }
             ]) == :ok
    end

    test "returns error for guarantees not ordered by core_index" do
      assert Guarantee.validate([
               %Guarantee{
                 work_report: %WorkReport{core_index: 2},
                 timeslot: 100,
                 credential: [{1, <<1::512>>}, {2, <<2::512>>}]
               },
               %Guarantee{
                 work_report: %WorkReport{core_index: 1},
                 timeslot: 100,
                 credential: [{1, <<3::512>>}, {2, <<4::512>>}]
               }
             ]) ==
               {:error, "Guarantees not ordered by core_index"}
    end

    test "returns error for duplicate core_index in guarantees" do
      assert Guarantee.validate([
               %Guarantee{
                 work_report: %WorkReport{core_index: 1},
                 timeslot: 100,
                 credential: [{1, <<1::512>>}, {2, <<2::512>>}]
               },
               %Guarantee{
                 work_report: %WorkReport{core_index: 1},
                 timeslot: 100,
                 credential: [{1, <<3::512>>}, {2, <<4::512>>}]
               }
             ]) ==
               {:error, "Duplicate core_index found in guarantees"}
    end

    test "returns error for invalid credential length" do
      assert Guarantee.validate([
               %Guarantee{
                 work_report: %WorkReport{core_index: 1},
                 timeslot: 100,
                 credential: [{1, <<1::512>>}]
               }
             ]) ==
               {:error, "Invalid credentials in one or more guarantees"}
    end

    test "returns error for credentials not ordered by validator_index" do
      assert Guarantee.validate([
               %Guarantee{
                 work_report: %WorkReport{core_index: 1},
                 timeslot: 100,
                 credential: [{2, <<1::512>>}, {1, <<2::512>>}]
               }
             ]) ==
               {:error, "Invalid credentials in one or more guarantees"}
    end

    test "returns error for duplicate validator_index in credentials" do
      assert Guarantee.validate([
               %Guarantee{
                 work_report: %WorkReport{core_index: 1},
                 timeslot: 100,
                 credential: [{1, <<1::512>>}, {1, <<2::512>>}]
               }
             ]) ==
               {:error, "Invalid credentials in one or more guarantees"}
    end

    test "handles empty list of guarantees" do
      assert Guarantee.validate([]) == :ok
    end

    test "validates a single guarantee correctly" do
      assert Guarantee.validate([
               %Guarantee{
                 work_report: %WorkReport{core_index: 1},
                 timeslot: 100,
                 credential: [{1, <<1::512>>}, {2, <<2::512>>}]
               }
             ]) == :ok
    end
  end
end
