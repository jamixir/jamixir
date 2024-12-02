defmodule ReportsTestVectorsTest do
  alias Util.Hash
  use ExUnit.Case
  import Mox
  import ReportsTestVectors
  setup :verify_on_exit!

  setup(do: setup_all())

  describe "vectors" do
    setup do
      stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
        {:ok, %{vrf_signature_output: Hash.zero()}}
      end)

      Application.put_env(:jamixir, :validator_statistics, ValidatorStatisticsMock)

      on_exit(fn ->
        Application.put_env(:jamixir, :validator_statistics, ValidatorStatistics)
      end)

      :ok
    end

    test "verify reports tiny vectors" do
      execute_test("core_engaged-1", "reports/tiny")
    end

    Enum.each(files_to_test(), fn file_name ->
      @tag file_name: file_name
      test "verify reports tiny vectors #{file_name}", %{file_name: file_name} do
        execute_test(file_name, "reports/tiny")
      end
    end)
  end
end
