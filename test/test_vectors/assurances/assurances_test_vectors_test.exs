defmodule AssurancesTestVectorsTest do
  use ExUnit.Case
  import Mox
  import AssurancesTestVectors
  import TestVectorUtil
  setup :verify_on_exit!

  setup(do: setup_all())

  describe "vectors" do
    define_vector_tests("assurances")
  end
end
