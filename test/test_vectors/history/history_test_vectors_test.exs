defmodule HistoryTestVectorsTest do
  alias Util.Hash
  use ExUnit.Case, async: false
  import Mox
  import HistoryTestVectors
  setup :verify_on_exit!

  defmodule TimeMock do
    def validate_block_timeslot(_), do: :ok
  end

  setup_all do
    # Application.put_env(:jamixir, :accumulation_module, MockAccumulation)
    Application.put_env(:jamixir, Util.Time, TimeMock)
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    Application.put_env(:jamixir, :original_modules, [])

    on_exit(fn ->
      # Application.put_env(:jamixir, :accumulation_module, System.State.Accumulation)
      Application.delete_env(:jamixir, Util.Time)
      Application.delete_env(:jamixir, :original_modules)
      Application.delete_env(:jamixir, :header_seal)
    end)

    :ok
  end

  describe "vectors" do
    setup do
      stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
        {:ok, %{vrf_signature_output: Hash.zero()}}
      end)

      :ok
    end

    Enum.each(files_to_test(), fn file_name ->
      @tag file_name: file_name
      @tag :tiny_test_vectors
      test "verify history vectors #{file_name}", %{file_name: file_name} do
        execute_test(file_name, "history/data")
      end
    end)
  end
end
