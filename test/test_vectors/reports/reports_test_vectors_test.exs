defmodule ReportsTestVectorsTest do
  alias Block.Extrinsic.Guarantee.WorkReport
  alias System.State.CoreReport
  use ExUnit.Case
  import Mox
  import ReportsTestVectors
  import TestVectorUtil
  import TestHelper

  setup :verify_on_exit!

  setup_all do
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    Application.put_env(:jamixir, :validator_statistics, ValidatorStatisticsMock)
    Application.put_env(:jamixir, :accumulation, MockAccumulation)

    Application.put_env(:jamixir, :original_modules, [
      Block.Extrinsic.Guarantee,
      Util.Collections,
      :validate_unique_and_ordered,
      CoreReport,
      WorkReport
    ])

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.put_env(:jamixir, :validator_statistics, System.State.ValidatorStatistics)
      Application.delete_env(:jamixir, :original_modules)
      Application.delete_env(:jamixir, :accumulation)
    end)

    :ok
  end

  describe "vectors" do
    setup do

      mock_header_seal()

      :ok
    end

    define_vector_tests("reports")
  end
end
