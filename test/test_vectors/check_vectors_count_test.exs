defmodule CheckVectorsCountTest do
  use ExUnit.Case
  import TestVectorUtil

  @moduletag :check_vectors_count

  describe "count test vector files" do
    test "assurances" do
      assert_count(AssurancesTestVectors, "./stf/assurances/tiny")
    end

    test "codec" do
      assert_count(CodecVectors, "./codec/tiny")
    end

    test "disputes" do
      assert_count(DisputesTestVectors, "./stf/disputes/tiny")
    end

    test "history" do
      assert_count(HistoryTestVectors, "./stf/history/tiny")
    end

    test "preimages" do
      assert_count(PreimagesTestVectors, "./stf/preimages/tiny")
    end

    test "reports" do
      assert_count(ReportsTestVectors, "./stf/reports/tiny")
    end

    test "safrole" do
      assert_count(SafroleTestVectors, "./stf/safrole/tiny")
    end

    test "statistics" do
      assert_count(StatisticsTestVectors, "./stf/statistics/tiny")
    end

    test "accumulate" do
      assert_count(AccumulateTestVectors, "./stf/accumulate/tiny")
    end
  end

  def assert_count(module, path) do
    assert MapSet.new(module.files_to_test()) == MapSet.new(list_test_files(path))
  end
end
