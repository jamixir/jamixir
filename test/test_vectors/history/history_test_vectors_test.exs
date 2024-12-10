defmodule HistoryTestVectorsTest do
  use ExUnit.Case
  import Mox
  import HistoryTestVectors
  import TestVectorUtil

  setup :verify_on_exit!

  setup_all do
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    Application.put_env(:jamixir, :accumulation, MockAccumulation)
    Application.put_env(:jamixir, :original_modules, [])

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

    Enum.each(files_to_test(), fn file_name ->
      @tag file_name: file_name
      test "verify history vectors #{file_name}", %{file_name: file_name} do
        execute_test(file_name, "history/data")
      end
    end)
  end
end
