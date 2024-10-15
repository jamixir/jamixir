defmodule WConstantsMock do
  def validator_count, do: 6
  def core_count, do: 2
end

defmodule WorkReportTest do
  use ExUnit.Case
  import Jamixir.Factory
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
end
