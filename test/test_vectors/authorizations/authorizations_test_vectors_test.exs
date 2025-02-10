defmodule AuthorizationTestVectorsTest do
  alias System.State.AuthorizerPool
  use ExUnit.Case
  import Mox
  import AuthorizationsTestVectors
  import TestHelper
  import TestVectorUtil

  setup :verify_on_exit!

  setup do
    RingVrf.init_ring_context()

    Application.put_env(:jamixir, :header_seal, HeaderSealMock)

    Application.put_env(:jamixir, :original_modules, [AuthorizerPool])

    mock_header_seal()

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  describe "vectors" do
    define_vector_tests("authorizations")
  end
end
