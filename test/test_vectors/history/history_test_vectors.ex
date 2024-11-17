defmodule HistoryTestVectors do
  alias Util.Hash
  alias Block.Extrinsic
  alias Block.Extrinsic.Disputes
  import TestVectorUtil
  use ExUnit.Case, async: false
  import Mox

  @owner "davxy"
  @repo "jam-test-vectors"
  @branch "polkajam-vectors"

  def files_to_test, do: [for(i <- 1..1, do: "progress_blocks_history-#{i}")] |> List.flatten()

  def tested_keys, do: [:recent_history]

  def execute_test(file_name, path) do
    {:ok, json_data} =
      fetch_and_parse_json(file_name <> ".json", path, @owner, @repo, @branch)

    header = %{
      parent_state_root: json_data[:input][:parent_state_root],
      slot: 5
    }

    guarantees =
      for w <- json_data[:input][:work_packages] do
        %{
          report: %{package_spec: w, results: []},
          signatures: [
            %{validator_index: 1, signature: Hash.zero()},
            %{validator_index: 1, signature: Hash.zero()}
          ]
        }
      end

    extrinsic =
      Map.from_struct(%Extrinsic{})
      |> Map.put(:disputes, Map.from_struct(%Disputes{}))
      |> Map.put(:guarantees, guarantees)

    stub(MockAccumulation, :accumulate, fn _, _, _, _ ->
      {:ok, %{beefy_commitment_map: json_data[:input][:accumulate_root]}}
    end)

    assert_expected_results(json_data, tested_keys(), file_name, extrinsic, header)
  end
end
