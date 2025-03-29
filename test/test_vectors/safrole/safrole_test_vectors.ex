defmodule SafroleTestVectors do
  import TestVectorUtil
  import Mox
  use ExUnit.Case

  define_repo_variables()

  def files_to_test,
    do:
      [
        for(i <- 1..4, do: "enact-epoch-change-with-no-tickets-#{i}"),
        "enact-epoch-change-with-padding-1",
        for(i <- 1..9, do: "publish-tickets-no-mark-#{i}"),
        for(i <- 1..5, do: "publish-tickets-with-mark-#{i}"),
        "skip-epoch-tail-1",
        "skip-epochs-1"
      ]
      |> List.flatten()

  def tested_keys,
    do: [
      :slot,
      :entropy_pool,
      :prev_validators,
      :curr_validators,
      {:safrole, :slot_sealers},
      {:safrole, :pending},
      {:safrole, :ticket_accumulator},
      {:safrole, :epoch_root}
    ]

  def execute_test(file_name, path) do
    {:ok, json_data} = fetch_and_parse_json(file_name <> ".json", path, @owner, @repo, @branch)

    psi = %{good: [], bad: [], wonky: [], offenders: json_data[:pre_state][:post_offenders]}
    json_data = put_in(json_data[:pre_state][:psi], psi)
    json_data = put_in(json_data[:post_state][:psi], psi)

    stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
      {:ok, %{vrf_signature_output: json_data[:input][:entropy] |> JsonDecoder.from_json()}}
    end)

    assert_expected_results(json_data, tested_keys(), file_name)
  end
end
