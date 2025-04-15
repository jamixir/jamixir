defmodule ReportsTestVectors do
  import TestVectorUtil
  import TestHelper
  alias Block.Extrinsic
  alias Block.Extrinsic.Disputes
  use ExUnit.Case

  def files_to_test,
    do:
      [
        "anchor_not_recent-1",
        "bad_beefy_mmr-1",
        "bad_code_hash-1",
        "bad_core_index-1",
        "bad_service_id-1",
        "bad_signature-1",
        "bad_state_root-1",
        "bad_validator_index-1",
        "big_work_report_output-1",
        "core_engaged-1",
        "dependency_missing-1",
        "duplicate_package_in_recent_history-1",
        "duplicated_package_in_report-1",
        "future_report_slot-1",
        "high_work_report_gas-1",
        "many_dependencies-1",
        "multiple_reports-1",
        "no_enough_guarantees-1",
        for(i <- 1..2, do: "not_authorized-#{i}"),
        "not_sorted_guarantor-1",
        "out_of_order_guarantees-1",
        "report_before_last_rotation-1",
        "report_curr_rotation-1",
        "report_prev_rotation-1",
        for(i <- 1..6, do: "reports_with_dependencies-#{i}"),
        for(i <- 1..2, do: "segment_root_lookup_invalid-#{i}"),
        "service_item_gas_too_low-1",
        "too_big_work_report_output-1",
        "too_high_work_report_gas-1",
        "too_many_dependencies-1",
        "with_avail_assignments-1",
        "wrong_assignment-1"
      ]
      |> List.flatten()

  def tested_keys,
    do: [
      :core_reports,
      :curr_validators,
      :prev_validators,
      :entropy_pool,
      :services
    ]

  define_repo_variables()

  def execute_test(file_name, path) do
    {:ok, json_data} = fetch_and_parse_json("#{file_name}.json", path, @owner, @repo, @branch)

    extrinsic =
      Map.from_struct(%Extrinsic{})
      |> Map.put(:guarantees, json_data[:input][:guarantees])
      |> Map.put(:disputes, Map.from_struct(%Disputes{}))

    ok_output = json_data[:output][:ok]

    mock_statistics()

    header =
      Map.merge(if(ok_output == nil, do: %{}, else: ok_output), json_data[:input])

    json_data = put_in(json_data[:pre_state][:slot], json_data[:input][:slot])
    assert_expected_results(json_data, tested_keys(), file_name, extrinsic, header)
  end
end
