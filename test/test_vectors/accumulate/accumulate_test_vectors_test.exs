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

    test "reports test vectors" do
      execute_test("enqueue_and_unlock_chain-2", "stf/accumulate/tiny")
    end

    define_vector_tests("accumulate")
  end
end
