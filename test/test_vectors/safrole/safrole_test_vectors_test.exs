defmodule SafroleTinyTestVectors do
  use ExUnit.Case
  import Mox
  import SafroleTestVectors
  import TestVectorUtil

  setup :verify_on_exit!

  setup_all(do: setup_all())

  describe "vectors" do
    define_vector_tests("safrole")
  end
end
