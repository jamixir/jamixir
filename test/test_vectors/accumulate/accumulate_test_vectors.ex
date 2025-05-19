defmodule AccumulateTestVectors do
  alias Block.Extrinsic
  alias Block.Extrinsic.Disputes
  import TestVectorUtil
  use ExUnit.Case
  import Mox

  define_repo_variables()

  def files_to_test,
    do:
      [
        "accumulate_ready_queued_reports-1",
        for(i <- 1..4, do: "enqueue_and_unlock_chain-#{i}"),
        for(i <- 1..5, do: "enqueue_and_unlock_chain_wraps-#{i}"),
        for(i <- 1..2, do: "enqueue_and_unlock_simple-#{i}"),
        for(i <- 1..2, do: "enqueue_and_unlock_with_sr_lookup-#{i}"),
        for(i <- 1..4, do: "enqueue_self_referential-#{i}"),
        "no_available_reports-1",
        "process_one_immediate_report-1",
        for(i <- 1..2, do: "queues_are_shifted-#{i}"),
        for(i <- 1..3, do: "ready_queue_editing-#{i}"),
        "same_code_different_services-1"
      ]
      |> List.flatten()

  def tested_keys,
    do: [
      :timeslot,
      :entropy_pool,
      :services,
      :ready_to_accumulate,
      :accumulation_history,
      :privileged_services,
      {:validator_statistics, :service_statistics, &extract_accumulation_count_from_stats/1}
    ]

  def extract_accumulation_count_from_stats(stats) do
    case Map.values(stats) |> Enum.at(0) do
      nil -> nil
      v -> elem(v.accumulation, 0)
    end
  end

  def execute_test(file_name, path) do
    {:ok, json_data} =
      fetch_and_parse_json(file_name <> ".json", path, @owner, @repo, @branch)

    extrinsic =
      Map.from_struct(%Extrinsic{})
      |> Map.put(:disputes, Map.from_struct(%Disputes{}))

    ValidatorStatisticsMock
    |> stub(:do_transition, fn _, _, _, _, _, _, _ -> {:ok, "mockvalue"} end)

    header = json_data[:input]

    json_data =
      put_in(json_data[:pre_state][:entropy], for(_ <- 1..4, do: json_data[:pre_state][:entropy]))

    mock_safrole = %{
      gamma_k: for(_ <- 1..Constants.validator_count(), do: %{}),
      gamma_s: %{keys: []},
      gamma_z: "0x00",
      gamma_a: []
    }

    json_data = put_in(json_data[:pre_state], Map.merge(json_data[:pre_state], mock_safrole))

    core_reports =
      for(
        r <- json_data[:input][:reports],
        do: %{timeout: json_data[:input][:slot], report: r}
      )

    json_data = put_in(json_data[:pre_state][:rho], core_reports)

    json_data =
      put_in(
        json_data[:post_state][:entropy],
        for(_ <- 1..4, do: json_data[:post_state][:entropy])
      )

    json_data = put_vector_services_stats_on_state(json_data)

    assert_expected_results(json_data, tested_keys(), file_name, extrinsic, header)
  end
end
