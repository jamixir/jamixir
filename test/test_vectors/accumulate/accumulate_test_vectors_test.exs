defmodule AccumulateTestVectorsTest do
  use ExUnit.Case
  import Mox
  import TestHelper
  import TestVectorUtil
  import AccumulateTestVectors

  setup :verify_on_exit!

  setup_all do
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)

    Application.put_env(:jamixir, :original_modules, [
      Accumulation,
      WorkReport,
      ValidatorStatistics
    ])

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.delete_env(:jamixir, :original_modules)
    end)
  end

  describe "vectors" do
    setup do
      mock_header_seal()
      :ok
    end

    # test "accumulate vectors" do
    #   # Ensure the test vectors are defined and can be run
    #   execute_test("accumulate_ready_queued_reports-1", "accumulate/tiny")
    # end

    # TODO accumulate vectors are failing after traces
    define_vector_tests("accumulate")
  end
end
