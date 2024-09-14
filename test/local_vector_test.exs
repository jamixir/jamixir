defmodule LocalVectorTest do
  use ExUnit.Case
  alias Block.Header
  import Mox
  import TestHelper
  setup :verify_on_exit!

  @vector_dir "test/test_vectors"

  describe "test vectors" do
    setup do
      Application.put_env(:jamixir, :header_seal, HeaderSealMock)
      Application.put_env(:jamixir, :validator_statistics, ValidatorStatisticsMock)

      on_exit(fn ->
        Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
        Application.put_env(:jamixir, :validator_statistics, ValidatorStatistics)
      end)

      :ok
    end

    test "verify test vector for enact-epoch-change-with-no-tickets-1.json" do
      file_name = "enact-epoch-change-with-no-tickets-1.json"
      {:ok, json_data} = read_local_json(file_name)
      vrf_output = json_data["input"]["entropy"]

      HeaderSealMock
      |> expect(:do_validate_header_seals, fn _, _, _, _ ->
        {:ok, %{vrf_signature_output: vrf_output}}
      end)

      ValidatorStatisticsMock
      |> expect(:posterior_validator_statistics, 1, fn _, _, _, _, _ -> "mockvalue" end)

      assert_expected_results(json_data)
    end
  end

  defp read_local_json(file_name) do
    file_path = Path.join(@vector_dir, file_name)

    case File.read(file_path) do
      {:ok, contents} ->
        {:ok, Jason.decode!(contents)}

      {:error, reason} ->
        IO.puts("Failed to read file: #{reason}")
        {:error, :failed_to_read}
    end
  end

  defp assert_expected_results(json_data) do
    # Translate JSON data into your system modules and run assertions
    # Example:
    pre_state = System.State.from_json(json_data["pre_state"])
    header = %Header{timeslot: json_data["input"]["slot"]}

    same_state?(
      System.State.from_json(json_data["post_state"]),
      System.State.add_block(pre_state, %Block{header: header, extrinsic: %Block.Extrinsic{}})
    )
  end
end
