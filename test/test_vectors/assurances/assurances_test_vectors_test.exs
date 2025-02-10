defmodule AssurancesTestVectorsTest do
  alias Util.Collections
  use ExUnit.Case
  import Mox
  import AssurancesTestVectors
  import TestHelper
  import TestVectorUtil

  setup :verify_on_exit!

  setup do
    RingVrf.init_ring_context()

    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    Application.put_env(:jamixir, :accumulation, MockAccumulation)
    Application.put_env(:jamixir, :validator_statistics, ValidatorStatisticsMock)

    Application.put_env(:jamixir, :original_modules, [
      :validate,
      # System.State.Judgements,
      Collections,
      System.State.CoreReport,
      Block.Extrinsic.Assurance,
      Block.Extrinsic.Guarantee.WorkReport
    ])

    mock_header_seal()
    mock_accumulate()

    stub(ValidatorStatisticsMock, :do_transition, fn _, _, _, _, _, _ ->
      {:ok, "mockvalue"}
    end)

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.put_env(:jamixir, :validator_statistics, System.State.ValidatorStatistics)
      Application.delete_env(:jamixir, :accumulation)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  describe "vectors" do
    define_vector_tests("assurances")
  end
end
