defmodule ReportsTestVectorsTest do
  alias Util.Hash
  use ExUnit.Case
  import Mox
  import ReportsTestVectors
  import TestVectorUtil

  setup :verify_on_exit!

  setup_all(do: setup_all())

  describe "vectors" do
    setup do
      stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
        {:ok, %{vrf_signature_output: Hash.zero()}}
      end)

      :ok
    end

    define_vector_tests("reports")
  end
end
