defmodule CheckVectorsCountTest do
  use ExUnit.Case
  import TestVectorUtil

  @moduletag :check_vectors_count

  describe "count test vector files" do
    test "assurances" do
      assert_count(AssurancesTestVectors, "./assurances/tiny")
    end

    test "codec" do
      assert_count(CodecVectors, "./codec/data")
    end

    test "disputes" do
      assert_count(DisputesTestVectors, "./disputes/tiny")
    end

    test "history" do
      assert_count(HistoryTestVectors, "./history/data")
    end

    test "preimages" do
      assert_count(PreimagesTestVectors, "./preimages/data")
    end

    test "reports" do
      assert_count(ReportsTestVectors, "./reports/tiny")
    end

    test "safrole" do
      assert_count(SafroleTestVectors, "./safrole/tiny")
    end

    test "statistics" do
      assert_count(StatisticsTestVectors, "./statistics/tiny")
    end

    test "accumulate" do
      assert_count(AccumulateTestVectors, "./accumulate/tiny")
    end
  end

  def assert_count(module, path) do
    assert MapSet.new(module.files_to_test()) == MapSet.new(list_test_files(path))
  end
end
