defmodule WConstantsMock do
  def validator_count, do: 6
  def core_count, do: 2
end

defmodule WorkReportTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias System.State.Ready
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Util.Hash

  setup do
    {:ok,
     wr:
       build(:work_report,
         specification: build(:availability_specification, work_package_hash: Hash.one())
       )}
  end

  test "encode/1 smoke test", %{wr: wr} do
    assert Codec.Encoder.encode(wr) ==
             "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\x02\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x03\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x03\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04\x05\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\x01\x03\x02\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\x03\0\0\0\0\0\0\0\0\x01\x04\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\x03\0\0\0\0\0\0\0\0\x01\x04"
  end

  describe "valid_size?/1" do
    test "returns true for a valid work report", %{wr: wr} do
      assert WorkReport.valid_size?(wr)
    end

    test "returns false when segment_root_lookup has more than 8 entries" do
      invalid_wr =
        build(:work_report,
          segment_root_lookup: for(i <- 1..9, into: %{}, do: {<<i::256>>, <<i::256>>})
        )

      refute WorkReport.valid_size?(invalid_wr)
    end

    test "returns false when encoded size exceeds max_work_report_size" do
      large_output = String.duplicate("a", Constants.max_work_report_size())
      invalid_wr = build(:work_report, output: large_output)
      refute WorkReport.valid_size?(invalid_wr)
    end
  end

  describe "available_work_reports/2" do
    setup do
      # Create mock assurances using factory
      # 6 validators / 2 cores
      assurances = [
        build(:assurance, bitfield: <<0b10::2>>),
        build(:assurance, bitfield: <<0b10::2>>),
        build(:assurance, bitfield: <<0b10::2>>),
        build(:assurance, bitfield: <<0b11::2>>),
        build(:assurance, bitfield: <<0b11::2>>),
        build(:assurance, bitfield: <<0b00::2>>)
      ]

      # Create mock core reports using factory
      core_reports = [
        build(:core_report, work_report: build(:work_report, core_index: 0)),
        build(:core_report, work_report: build(:work_report, core_index: 1))
      ]

      Application.put_env(:jamixir, Constants, WConstantsMock)

      on_exit(fn ->
        Application.delete_env(:jamixir, Constants)
      end)

      %{assurances: assurances, core_reports: core_reports}
    end

    test "returns work reports for cores with sufficient assurances", %{
      assurances: assurances,
      core_reports: core_reports
    } do
      result = WorkReport.available_work_reports(assurances, core_reports)

      assert length(result) == 1
      assert Enum.map(result, & &1.core_index) == [0]
    end

    test "returns empty list when no cores have sufficient assurances" do
      assurances =
        Enum.map(1..6, fn _ ->
          build(:assurance, bitfield: <<0b00::2>>)
        end)

      result = WorkReport.available_work_reports(assurances, [])

      assert result == []
    end

    test "handles case when all cores have sufficient assurances", %{core_reports: core_reports} do
      assurances =
        Enum.map(1..6, fn _ -> build(:assurance, bitfield: <<0b11::2>>) end)

      result = WorkReport.available_work_reports(assurances, core_reports)

      assert length(result) == 2
      assert Enum.map(result, & &1.core_index) == [0, 1]
    end

    test "handles empty assurances list" do
      result = WorkReport.available_work_reports([], [])

      assert result == []
    end
  end

  describe "split_by_prerequisites/1" do
    test "splits work reports based on prerequisites" do
      w1 = build(:work_report, refinement_context: %{prerequisite: nil}, segment_root_lookup: %{})

      w2 =
        build(:work_report,
          refinement_context: %{prerequisite: <<1::256>>},
          segment_root_lookup: %{}
        )

      w3 = build(:work_report, refinement_context: %{prerequisite: nil}, segment_root_lookup: %{})

      w4 =
        build(:work_report,
          refinement_context: %{prerequisite: <<2::256>>},
          segment_root_lookup: %{}
        )

      w5 =
        build(:work_report,
          refinement_context: %{prerequisite: <<3::256>>},
          segment_root_lookup: %{}
        )

      assert {[^w1, ^w3], [^w2, ^w4, ^w5]} =
               WorkReport.split_by_prerequisites([w1, w2, w3, w4, w5])
    end

    test "handles empty list" do
      assert {[], []} = WorkReport.split_by_prerequisites([])
    end

    test "handles list with only prerequisites" do
      w1 =
        build(:work_report,
          refinement_context: %{prerequisite: <<1::256>>},
          segment_root_lookup: %{}
        )

      w2 =
        build(:work_report,
          refinement_context: %{prerequisite: <<2::256>>},
          segment_root_lookup: %{}
        )

      assert {[], [^w1, ^w2]} = WorkReport.split_by_prerequisites([w1, w2])
    end

    test "handles list with only non-prerequisites" do
      w1 = build(:work_report, refinement_context: %{prerequisite: nil}, segment_root_lookup: %{})
      w2 = build(:work_report, refinement_context: %{prerequisite: nil}, segment_root_lookup: %{})

      assert {[^w1, ^w2], []} = WorkReport.split_by_prerequisites([w1, w2])
    end
  end

  describe "with_dependencies/1" do
    test "returns work report with its dependencies" do
      w =
        build(:work_report,
          refinement_context: %{prerequisite: <<1::256>>},
          segment_root_lookup: %{<<2::256>> => <<3::256>>}
        )

      assert {^w, deps} = WorkReport.with_dependencies(w)
      assert deps == MapSet.new([<<1::256>>, <<2::256>>])
    end
  end

  describe "edit_queue/2" do
    test "filters and updates the queue based on accumulated work" do
      w1 =
        build(:work_report,
          specification: %{work_package_hash: <<1::256>>},
          segment_root_lookup: %{}
        )

      w2 =
        build(:work_report,
          specification: %{work_package_hash: <<2::256>>},
          segment_root_lookup: %{<<3::256>> => <<4::256>>}
        )

      r = [{w1, MapSet.new()}, {w2, MapSet.new([<<3::256>>])}]
      x = %{<<2::256>> => <<5::256>>}

      result = WorkReport.edit_queue(r, x)
      assert [{^w1, empty_set}] = result
      assert MapSet.equal?(empty_set, MapSet.new())
    end

    test "handles empty queue" do
      assert [] == WorkReport.edit_queue([], %{<<1::256>> => <<2::256>>})
    end
  end

  describe "create_package_root_map/1" do
    test "creates a map of work package hashes to segment roots" do
      w1 =
        build(:work_report,
          specification: %{work_package_hash: <<1::256>>, exports_root: <<2::256>>}
        )

      w2 =
        build(:work_report,
          specification: %{work_package_hash: <<3::256>>, exports_root: <<4::256>>}
        )

      assert %{<<1::256>> => <<2::256>>, <<3::256>> => <<4::256>>} =
               WorkReport.create_package_root_map([w1, w2])
    end
  end

  describe "accumulation_priority_queue/2" do
    test "returns work reports in accumulation priority order" do
      w1 =
        build(:work_report,
          specification: %{work_package_hash: <<1::256>>, exports_root: <<5::256>>},
          segment_root_lookup: %{}
        )

      w2 =
        build(:work_report,
          specification: %{work_package_hash: <<2::256>>, exports_root: <<6::256>>},
          segment_root_lookup: %{<<3::256>> => <<4::256>>}
        )

      r = [{w1, MapSet.new()}, {w2, MapSet.new([<<3::256>>])}]
      a = %{}

      assert [^w1, ^w2] = WorkReport.accumulation_priority_queue(r, a)
    end
  end

  describe "accumulatable_work_reports/4" do
    setup do
      work_reports =
        for i <- 1..4 do
          build(:work_report,
            core_index: i,
            specification: %{work_package_hash: <<i::256>>, exports_root: <<i::256>>},
            refinement_context: %{prerequisite: nil},
            segment_root_lookup: %{}
          )
        end

      [w1, w2, w3, w4] = work_reports

      # Modify w2 to have a prerequisite or non-empty segment_root_lookup
      w2 = %{
        w2
        | refinement_context: %{prerequisite: <<1::256>>},
          segment_root_lookup: %{<<5::256>> => <<6::256>>}
      }

      %{
        w1: w1,
        w2: w2,
        w3: w3,
        w4: w4
      }
    end

    test "returns accumulatable work reports", %{w1: w1, w2: w2, w3: w3, w4: w4} do
      block_timeslot = 1
      accumulation_history = [%{}]

      ready_to_accumulate = [
        [
          %Ready{work_report: w3, dependencies: MapSet.new()}
        ],
        [%Ready{work_report: w4, dependencies: MapSet.new()}]
      ]

      result =
        WorkReport.accumulatable_work_reports(
          [w1, w2],
          block_timeslot,
          accumulation_history,
          ready_to_accumulate
        )

      assert [^w1, ^w3, ^w4, ^w2] = result
    end
  end
end
