defmodule PreimagesTestVectors do
  alias Block.Extrinsic
  alias Block.Extrinsic.Disputes
  alias System.State.Services
  import TestVectorUtil
  use ExUnit.Case
  import Mox

  define_repo_variables()

  def files_to_test,
    do: [
      "preimage_needed-1",
      "preimage_needed-2",
      # "preimage_not_needed-1",
      "preimage_not_needed-2"
    ]

  def tested_keys, do: [:services]

  def execute_test(file_name, path) do
    {:ok, json_data} =
      fetch_and_parse_json(file_name <> ".json", path, @owner, @repo, @branch)

    header = %{
      slot: json_data[:input][:slot]
    }

    extrinsic =
      Map.from_struct(%Extrinsic{})
      |> Map.put(:disputes, Map.from_struct(%Disputes{}))
      |> Map.put(:preimages, json_data[:input][:preimages])

    pre_services = Services.from_json(json_data[:pre_state][:accounts] || [])

    stub(MockAccumulation, :do_transition, fn _, _, _, _ ->
      {:ok,
       %{
         beefy_commitment: <<>>,
         authorizer_queue: [],
         services: pre_services,
         next_validators: [],
         privileged_services: %{},
         accumulation_history: %{},
         ready_to_accumulate: %{}
       }}
    end)

    json_data = put_in(json_data[:pre_state][:tau], json_data[:input][:slot])

    assert_expected_results(json_data, tested_keys(), file_name, extrinsic, header)
  end
end
