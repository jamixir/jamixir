defmodule ReportsTestVectorsTest do
  use ExUnit.Case
  import Mox
  import ReportsTestVectors
  import TestVectorUtil

  setup :verify_on_exit!

  setup_all(do: setup_all())

  describe "vectors" do
    setup do
      mock_header_seal()

      :ok
    end

    define_vector_tests("reports")
  end
end
