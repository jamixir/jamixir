defmodule AssurancesTestVectors do
  import TestVectorUtil
  alias Block.Extrinsic
  alias Block.Extrinsic.Disputes
  use ExUnit.Case

  @owner "davxy"
  @repo "jam-test-vectors"
  @branch "assurances"

  def files_to_test,
    do:
      [
        "assurance_for_not_engaged_core-1",
        "assurance_with_bad_attestation_parent-1",
        # supposed error on vector
        # "assurances_for_stale_report-1",
        "assurances_with_bad_signature-1",
        "assurances_with_bad_validator_index-1",
        "no_assurances-1",
        # supposed error on vector
        # "no_assurances_with_stale_report-1",
        "some_assurances-1"
      ]
      |> List.flatten()

  def tested_keys, do: [:core_reports, :curr_validators]

  def execute_test(file_name, path) do
    {:ok, json_data} =
      fetch_and_parse_json(file_name <> ".json", path, @owner, @repo, @branch)

    extrinsic =
      Map.from_struct(%Extrinsic{})
      |> Map.put(:disputes, Map.from_struct(%Disputes{}))
      |> Map.put(:assurances, json_data[:input][:assurances])

    ok_output = json_data[:output][:ok]

    header =
      Map.merge(if(ok_output == nil, do: %{}, else: ok_output), json_data[:input])

    json_data = put_in(json_data[:pre_state][:slot], json_data[:input][:slot])

    assert_expected_results(json_data, tested_keys(), file_name, extrinsic, header)
  end
end
