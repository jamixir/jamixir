defmodule StatisticsTestVectors do
  import TestVectorUtil
  use ExUnit.Case
  import Mox

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

    extrinsic = json_data[:input][:extrinsic]
    header = json_data[:input]

    stub(MockAccumulation, :do_accumulate, fn _, _, _, _ ->
      {:ok,
       %{
         beefy_commitment_map: <<>>,
         authorizer_queue: [],
         services: %{},
         next_validators: [],
         privileged_services: %{},
         accumulation_history: %{},
         ready_to_accumulate: %{}
       }}
    end)

    assert_expected_results(json_data, tested_keys(), file_name, extrinsic, header)
  end
end
