defmodule DisputesTinyTestVectors do
  use ExUnit.Case, async: false
  import Mox
  import DisputesTestVectors
  import TestVectorUtil

  setup :verify_on_exit!

  setup(do: setup_all())

  describe "vectors" do
    define_vector_tests("disputes")
  end
end
