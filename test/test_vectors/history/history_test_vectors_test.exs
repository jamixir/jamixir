defmodule HistoryTestVectorsTest do
  use ExUnit.Case
  import Mox
  import HistoryTestVectors
  import TestHelper
  import TestVectorUtil

  setup :verify_on_exit!

  setup_all do
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    Application.put_env(:jamixir, :accumulation, MockAccumulation)

    Application.put_env(:jamixir, :original_modules, [:transition])

    on_exit(fn ->
      Application.delete_env(:jamixir, :original_modules)
      Application.delete_env(:jamixir, :header_seal)
      Application.delete_env(:jamixir, :accumulation)
    end)

    :ok
  end

  describe "vectors" do
    setup do
      mock_header_seal()
      :ok
    end

    define_vector_tests("history")
  end
end
