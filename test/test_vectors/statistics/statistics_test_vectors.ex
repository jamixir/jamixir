defmodule StatisticsTestVectors do
  import TestVectorUtil
  use ExUnit.Case

  @owner "davxy"
  @repo "jam-test-vectors"
  @branch "statistics"

  def files_to_test,
    do: [
      "stats_with_empty_extrinsic-1",
      "stats_with_epoch_change-1",
      "stats_with_some_extrinsic-1"
    ]

  def tested_keys, do: [:pi]

  def execute_test(file_name, path) do
    {:ok, json_data} =
      fetch_and_parse_json(file_name <> ".json", path, @owner, @repo, @branch)

    mock_safrole = %{
      gamma_k: json_data[:pre_state][:kappa_prime],
      gamma_s: %{keys: []},
      gamma_z: "0x00",
      gamma_a: []
    }

    json_data = put_in(json_data[:pre_state], Map.merge(json_data[:pre_state], mock_safrole))

    extrinsic = json_data[:input][:extrinsic]
    header = json_data[:input]

    assert_expected_results(json_data, tested_keys(), file_name, extrinsic, header)
  end
end
