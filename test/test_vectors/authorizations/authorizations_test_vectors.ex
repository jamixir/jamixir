defmodule AuthorizationsTestVectors do
  alias Block.Extrinsic.Disputes
  import TestVectorUtil
  use ExUnit.Case

  define_repo_variables()

  def files_to_test, do: for(i <- 1..3, do: "progress_authorizations-#{i}")

  def tested_keys, do: [:authorizer_pool, :authorizer_queue]

  def execute_test(file_name, path) do
    {:ok, json_data} =
      fetch_and_parse_json(file_name <> ".json", path, @owner, @repo, @branch)

    guarantees =
      for %{core: c, auth_hash: a} <- json_data[:input][:auths] do
        %{report: %{core_index: c, authorizer_hash: a, results: []}, signatures: []}
      end

    extrinsic = %{guarantees: guarantees, tickets: [], assurances: [], preimages: []}
    extrinsic = put_in(extrinsic[:disputes], Map.from_struct(%Disputes{}))

    json_data = put_in(json_data[:input][:extrinsic], extrinsic)
    json_data = put_in(json_data[:pre_state][:tau], json_data[:input][:slot])

    header = json_data[:input]

    assert_expected_results(json_data, tested_keys(), file_name, extrinsic, header)
  end
end
