defmodule AccumulateTestVectorsTest do
  use ExUnit.Case
  import Mox
  import AccumulateTestVectors
  import TestVectorUtil
  import TestHelper

  setup :verify_on_exit!

  setup_all do
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    Application.put_env(:jamixir, :validator_statistics, ValidatorStatisticsMock)

    Application.put_env(:jamixir, :original_modules, [
      Accumulation,
      WorkReport
    ])

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.put_env(:jamixir, :validator_statistics, System.State.ValidatorStatistics)
      Application.delete_env(:jamixir, :original_modules)
    end)
  end

  describe "vectors" do
    setup do
      mock_header_seal()
      :ok
    end

    test "smoke" do
      execute_test("enqueue_and_unlock_chain_wraps-2", "accumulate/tiny")
    end

    define_vector_tests("accumulate")
  end
end
