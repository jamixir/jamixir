defmodule ReportsTestVectorsTest do
  use ExUnit.Case
  import Mox
  import ReportsTestVectors
  import TestVectorUtil

  setup :verify_on_exit!

  setup_all do
    RingVrf.init_ring_context()
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    Application.put_env(:jamixir, :validator_statistics, ValidatorStatisticsMock)

    Application.put_env(:jamixir, :original_modules, [
      Block.Extrinsic.Guarantee,
      Util.Collections,
      :validate_unique_and_ordered
    ])

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.put_env(:jamixir, :validator_statistics, System.State.ValidatorStatistics)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  describe "vectors" do
    setup do
      mock_header_seal()

      :ok
    end

    test "smoke" do
      # execute_test("high_work_report_gas-1", "reports/tiny")
    end

    define_vector_tests("reports")
  end
end
