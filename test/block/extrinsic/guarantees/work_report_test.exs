defmodule WorkReportTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block.Extrinsic.Guarantee.WorkReport

  setup do
    {:ok,
     wr:
       build(:work_report,
         specification: build(:availability_specification, work_package_hash: <<1::256>>)
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
end
