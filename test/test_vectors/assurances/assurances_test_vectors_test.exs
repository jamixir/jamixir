defmodule AssurancesTestVectorsTest do
  alias Util.Hash
  use ExUnit.Case
  import Mox
  import AssurancesTestVectors
  setup :verify_on_exit!

  setup(do: setup_all())

  describe "vectors" do
    setup do
      stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
        {:ok, %{vrf_signature_output: Hash.zero()}}
      end)

      Application.put_env(:jamixir, :accumulation, MockAccumulation)
      Application.put_env(:jamixir, :validator_statistics, ValidatorStatisticsMock)

      stub(ValidatorStatisticsMock, :do_calculate_validator_statistics_, fn _, _, _, _, _, _ ->
        {:ok, "mockvalue"}
      end)

      on_exit(fn ->
        Application.put_env(:jamixir, :validator_statistics, System.State.ValidatorStatistics)
        Application.delete_env(:jamixir, :accumulation)
      end)

      :ok
    end

    # test "smoke tiny vectors" do
    #   execute_test("no_assurances_with_stale_report-1", "assurances/tiny")
    # end

    Enum.each(files_to_test(), fn file_name ->
      @tag file_name: file_name
      test "verify reports tiny vectors #{file_name}", %{file_name: file_name} do
        execute_test(file_name, "assurances/tiny")
      end
    end)
  end
end
