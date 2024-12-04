defmodule DisputesTestVectors do
  alias Block.Extrinsic
  alias Util.Hash
  use ExUnit.Case
  import Mox
  import TestVectorUtil

  @owner "davxy"
  @repo "jam-test-vectors"
  @branch "disputes"

  def files_to_test,
    do:
      [
        "progress_invalidates_avail_assignments-1",
        for(i <- 1..2, do: "progress_with_bad_signatures-#{i}"),
        for(i <- 1..7, do: "progress_with_culprits-#{i}"),
        for(i <- 1..7, do: "progress_with_faults-#{i}"),
        "progress_with_no_verdicts-1",
        for(i <- 1..2, do: "progress_with_verdict_signatures_from_previous_set-#{i}"),
        for(i <- 1..6, do: "progress_with_verdicts-#{i}")
      ]
      |> List.flatten()

  def tested_keys, do: [:judgements, :core_reports, :timeslot, :curr_validators, :prev_validators]

  def setup_all do
    RingVrf.init_ring_context(Constants.validator_count())
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)

    Application.put_env(:jamixir, :original_modules, [
      :validate,
      System.State.Judgements,
      System.State.CoreReport,
      Block.Extrinsic.Disputes,
      Block.Extrinsic.Disputes.Culprit,
      Block.Extrinsic.Disputes.Fault,
      Block.Extrinsic.Disputes.Judgement,
      Block.Extrinsic.Disputes.Verdict
    ])

    stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
      {:ok, %{vrf_signature_output: Hash.zero()}}
    end)

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  def execute_test(file_name, path) do
    {:ok, json_data} =
      fetch_and_parse_json(file_name <> ".json", path, @owner, @repo, @branch)

    extrinsic =
      Map.from_struct(%Extrinsic{})
      |> Map.put(:disputes, json_data[:input][:disputes])

    ok_output = json_data[:output][:ok]

    header =
      Map.merge(if(ok_output == nil, do: %{}, else: ok_output), json_data[:input])
      |> Map.put(:slot, json_data[:pre_state][:tau])

    assert_expected_results(json_data, tested_keys(), file_name, extrinsic, header)
  end
end
