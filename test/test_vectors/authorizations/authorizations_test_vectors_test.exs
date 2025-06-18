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
# authorizer_queue_ doesn't match
# authorizer_pool_ depeneds on authorizer_queue_ => also doesn't match
# authorizer_queue_ is created in accumualtion.transition and has been changed in 0.6.7
# test vect
  describe "vectors" do
    define_vector_tests("authorizations")
  end
end
