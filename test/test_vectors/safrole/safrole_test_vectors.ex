defmodule SafroleTestVectors do
  import TestVectorUtil
  import Mox

  def files,
    do:
      [
        for(i <- 1..4, do: "enact-epoch-change-with-no-tickets-#{i}"),
        for(i <- 1..9, do: "publish-tickets-no-mark-#{i}"),
        for(i <- 1..5, do: "publish-tickets-with-mark-#{i}"),
        "skip-epoch-tail-1",
        "skip-epochs-1"
      ]
      |> List.flatten()

  def tested_keys, do: [:timeslot, :entropy_pool, :prev_validators, :curr_validators, :safrole]

  def execute_test(file_name, path) do
    {:ok, json_data} = fetch_and_parse_json(file_name <> ".json", path)

    stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
      {:ok, %{vrf_signature_output: json_data[:input][:entropy] |> JsonDecoder.from_json()}}
    end)

    assert_expected_results(json_data, tested_keys(), file_name)
  end
end
