defmodule Block.ExtrinsicTest do
  use ExUnit.Case

  alias Block.Extrinsic
  alias Block.Extrinsic.{Guarantee, Guarantee.WorkReport}

  describe "guarantees/1" do
    test "returns guarantees sorted by core_index" do
      guarantees = [
        %Guarantee{
          work_report: %WorkReport{core_index: 2},
          timeslot: 100,
          credential: [{1, <<1::512>>}]
        },
        %Guarantee{
          work_report: %WorkReport{core_index: 1},
          timeslot: 100,
          credential: [{2, <<2::512>>}]
        },
        %Guarantee{
          work_report: %WorkReport{core_index: 3},
          timeslot: 100,
          credential: [{3, <<3::512>>}]
        }
      ]

      extrinsic = %Extrinsic{guarantees: guarantees}
      sorted_guarantees = Extrinsic.unique_sorted_guarantees(extrinsic)

      assert Enum.map(sorted_guarantees, & &1.work_report.core_index) == [1, 2, 3]
    end

    test "ensures uniqueness of core_index across guarantees" do
      guarantees = [
        %Guarantee{
          work_report: %WorkReport{core_index: 1},
          timeslot: 100,
          credential: [{1, <<1::512>>}]
        },
        %Guarantee{
          work_report: %WorkReport{core_index: 1},
          timeslot: 100,
          credential: [{2, <<2::512>>}]
        },
        %Guarantee{
          work_report: %WorkReport{core_index: 2},
          timeslot: 100,
          credential: [{3, <<3::512>>}]
        }
      ]

      extrinsic = %Extrinsic{guarantees: guarantees}

      assert_raise ArgumentError, "Duplicate core_index found in guarantees", fn ->
        Extrinsic.unique_sorted_guarantees(extrinsic)
      end
    end

    test "returns guarantees with credentials sorted by validator_index" do
      guarantees = [
        %Guarantee{
          work_report: %WorkReport{core_index: 1},
          timeslot: 100,
          credential: [{2, <<1::512>>}, {1, <<2::512>>}]
        }
      ]

      extrinsic = %Extrinsic{guarantees: guarantees}
      sorted_guarantees = Extrinsic.unique_sorted_guarantees(extrinsic)

      assert hd(sorted_guarantees).credential == [{1, <<2::512>>}, {2, <<1::512>>}]
    end

    test "ensures uniqueness of validator_index within credentials" do
      guarantees = [
        %Guarantee{
          work_report: %WorkReport{core_index: 1},
          timeslot: 100,
          credential: [{1, <<1::512>>}, {1, <<2::512>>}]
        }
      ]

      extrinsic = %Extrinsic{guarantees: guarantees}

      assert_raise ArgumentError, "Duplicate validator_index found in credentials", fn ->
        Extrinsic.unique_sorted_guarantees(extrinsic)
      end
    end

    test "handles empty list of guarantees" do
      extrinsic = %Extrinsic{guarantees: []}
      assert Extrinsic.unique_sorted_guarantees(extrinsic) == []
    end

    test "returns a single guarantee unchanged" do
      guarantees = [
        %Guarantee{
          work_report: %WorkReport{core_index: 1},
          timeslot: 100,
          credential: [{1, <<1::512>>}]
        }
      ]

      extrinsic = %Extrinsic{guarantees: guarantees}
      assert Extrinsic.unique_sorted_guarantees(extrinsic) == guarantees
    end
  end
end
