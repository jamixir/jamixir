defmodule HistoryTestVectors do
  alias Block.Extrinsic
  alias Block.Extrinsic.Disputes
  alias Util.Hash
  import TestVectorUtil
  use ExUnit.Case
  import Mox

  define_repo_variables()

  def files_to_test, do: [for(i <- 1..4, do: "progress_blocks_history-#{i}")] |> List.flatten()

  def tested_keys, do: [:recent_history]

  def execute_test(file_name, path) do
    {:ok, json_data} =
      fetch_and_parse_json(file_name <> ".json", path, @owner, @repo, @branch)

    header = %{
      parent_state_root: json_data[:input][:parent_state_root],
      slot: 5,
      extrinsic_hash: json_data[:input][:header_hash]
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

    stub(MockAccumulation, :do_transition, fn _, _, _ ->
      %{
        beefy_commitment: JsonDecoder.from_json(json_data[:input][:accumulate_root]),
        authorizer_queue: [],
        services: %{},
        next_validators: [],
        privileged_services: %{},
        accumulation_history: %{},
        ready_to_accumulate: %{}
      }
    end)

    assert_expected_results(json_data, tested_keys(), file_name, extrinsic, header)
  end
end
