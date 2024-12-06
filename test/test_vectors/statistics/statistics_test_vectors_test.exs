defmodule StatisticsTestVectorsTest do
  use ExUnit.Case
  import Mox
  import StatisticsTestVectors
  import TestVectorUtil
  setup :verify_on_exit!

  setup do
    RingVrf.init_ring_context(Constants.validator_count())

    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    Application.put_env(:jamixir, :accumulation, MockAccumulation)

    Application.put_env(:jamixir, :original_modules, [
      System.State.ValidatorStatistics
    ])

    mock_header_seal()
    mock_accumulate()

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.delete_env(:jamixir, :accumulation)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  describe "vectors" do
    define_vector_tests("statistics")
  end
end
