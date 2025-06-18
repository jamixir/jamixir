defmodule AuthorizationTestVectorsTest do
  alias System.State.AuthorizerPool
  use ExUnit.Case
  import Mox
  import AuthorizationsTestVectors
  import TestHelper
  import TestVectorUtil

  setup :verify_on_exit!

  setup do
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)

    Application.put_env(:jamixir, :original_modules, [AuthorizerPool])

    mock_header_seal()

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  test "just one test" do
  execute_test("progress_authorizations-1", "stf/authorizations/tiny")
  end


# TODO
# our code already assumes the following PR, check later if it was accepted
# the pr adds a missing c subscript to the transformation of auth queue in 12.17
# without it, there is a dimensionality bug 2d matric turns into 3d tensor
# it is missing another c subscript
# https://github.com/gavofyork/graypaper/pull/437

  describe "vectors" do
    define_vector_tests("authorizations")
  end
end
