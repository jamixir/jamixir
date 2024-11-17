defmodule HistoryTestVectors do
  import TestVectorUtil
  alias Block.Extrinsic

  @owner "davxy"
  @repo "jam-test-vectors"
  @branch "polkajam-vectors"

  def files_to_test, do: [for(i <- 1..4, do: "progress_blocks_history-1-#{i}")] |> List.flatten()

  def tested_keys, do: [:recent_history]

  def execute_test(file_name, path) do
    {:ok, json_data} =
      fetch_and_parse_json(file_name <> ".json", path, @owner, @repo, @branch)

    extrinsic =
      Map.from_struct(%Extrinsic{})
      |> Map.put(:disputes, json_data[:input][:disputes])

    header = json_data[:input]

    assert_expected_results(
      json_data,
      tested_keys(),
      file_name,
      extrinsic,
      header
    )
  end

  describe "vectors" do
    setup do
      stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
        {:ok, %{vrf_signature_output: Hash.zero()}}
      end)

      :ok
    end

    Enum.each(DisputesTestVectors.files_to_test(), fn file_name ->
      @tag file_name: file_name
      @tag :tiny_test_vectors
      test "verify tiny test vectors #{file_name}", %{file_name: file_name} do
        DisputesTestVectors.execute_test(file_name, "disputes/tiny")
      end
    end)
  end
end
