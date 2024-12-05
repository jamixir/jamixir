defmodule StatisticsTestVectorsTest do
  use ExUnit.Case
  alias Util.Hash
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

    stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
      {:ok, %{vrf_signature_output: Hash.zero()}}
    end)

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
