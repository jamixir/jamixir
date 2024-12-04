defmodule AssurancesTestVectors do
  import TestVectorUtil
  alias Util.Hash
  alias Block.Extrinsic.Disputes
  alias Block.Extrinsic
  use ExUnit.Case
  import Mox

  @owner "davxy"
  @repo "jam-test-vectors"
  @branch "assurances"

  def files_to_test,
    do:
      [
        "assurance_for_not_engaged_core-1",
        "assurance_with_bad_attestation_parent-1",
        # "assurances_for_stale_report-1",
        "assurances_with_bad_signature-1",
        "assurances_with_bad_validator_index-1",
        "no_assurances-1",
        # "no_assurances_with_stale_report-1",
        "some_assurances-1"
      ]
      |> List.flatten()

  def tested_keys, do: [:core_reports, :curr_validators]

  def setup_all do
    RingVrf.init_ring_context(Constants.validator_count())

    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    Application.put_env(:jamixir, :accumulation, MockAccumulation)
    Application.put_env(:jamixir, :validator_statistics, ValidatorStatisticsMock)

    Application.put_env(:jamixir, :original_modules, [
      :validate,
      # System.State.Judgements,
      System.State.CoreReport,
      Block.Extrinsic.Assurance,
      Block.Extrinsic.Guarantee.WorkReport
    ])

    stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
      {:ok, %{vrf_signature_output: Hash.zero()}}
    end)

    stub(ValidatorStatisticsMock, :do_calculate_validator_statistics_, fn _, _, _, _, _, _ ->
      {:ok, "mockvalue"}
    end)

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.put_env(:jamixir, :validator_statistics, System.State.ValidatorStatistics)
      Application.delete_env(:jamixir, :accumulation)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

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

    stub(MockAccumulation, :do_accumulate, fn _, _, _, _ ->
      {:ok,
       %{
         beefy_commitment_map: <<>>,
         authorizer_queue: [],
         services: %{},
         next_validators: [],
         privileged_services: %{},
         accumulation_history: %{},
         ready_to_accumulate: %{}
       }}
    end)

    assert_expected_results(json_data, tested_keys(), file_name, extrinsic, header)
  end
end
