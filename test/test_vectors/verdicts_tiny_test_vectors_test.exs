defmodule VerdictsConstantsMock do
  def epoch_length, do: 12
  def ticket_submission_end, do: 10
end

defmodule TimeMock do
  def validate_timeslot_order(_, _), do: :ok
end

defmodule VerdictsTinyTestVectors do
  alias Block.Extrinsic
  alias Util.Hash
  use ExUnit.Case, async: false
  import Mox
  import TestVectorUtil
  setup :verify_on_exit!

  @owner "davxy"
  @repo "jam-test-vectors"
  @branch "disputes"
  @path "disputes/tiny"

  setup_all do
    RingVrf.init_ring_context(6)
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    Application.put_env(:jamixir, Constants, VerdictsConstantsMock)
    Application.put_env(:jamixir, Util.Time, TimeMock)

    Application.put_env(:jamixir, :original_modules, [
      System.State.Judgements,
      System.State.CoreReport,
      Block.Extrinsic.Disputes,
      Block.Extrinsic.Disputes.Culprit,
      Block.Extrinsic.Disputes.Fault,
      Block.Extrinsic.Disputes.Judgement,
      Block.Extrinsic.Disputes.Verdict
    ])

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.delete_env(:jamixir, Constants)
      Application.delete_env(:jamixir, Util.Time)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  describe "vectors" do
    test "verify epoch length" do
      assert Constants.epoch_length() == 12
    end

    files_to_test = [
      # "progress_invalidates_avail_assignments-1"
      "progress_with_bad_signatures-1",
      "progress_with_bad_signatures-2",
      "progress_with_culprits-1",
      "progress_with_culprits-2",
      "progress_with_culprits-3",
      "progress_with_culprits-4",
      "progress_with_culprits-5",
      "progress_with_culprits-6",
      "progress_with_culprits-7",
      "progress_with_faults-1",
      "progress_with_faults-2",
      "progress_with_faults-3",
      "progress_with_faults-4",
      "progress_with_faults-5",
      "progress_with_faults-6",
      "progress_with_faults-7",
      "progress_with_no_verdicts-1",
      "progress_with_verdict_signatures_from_previous_set-1",
      "progress_with_verdict_signatures_from_previous_set-2",
      "progress_with_verdicts-1",
      "progress_with_verdicts-2",
      "progress_with_verdicts-3",
      "progress_with_verdicts-4",
      "progress_with_verdicts-5",
      "progress_with_verdicts-6"
    ]

    Enum.each(files_to_test, fn file_name ->
      @tag file_name: file_name
      @tag :tiny_test_vectors
      test "verify tiny test vectors #{file_name}", %{file_name: file_name} do
        {:ok, json_data} =
          fetch_and_parse_json(file_name <> ".json", @path, @owner, @repo, @branch)

        HeaderSealMock
        |> stub(:do_validate_header_seals, fn _, _, _, _ ->
          {:ok, %{vrf_signature_output: Hash.zero()}}
        end)

        extrinsic =
          Map.from_struct(%Extrinsic{})
          |> Map.put(:disputes, json_data[:input][:disputes])

        ok_output = json_data[:output][:ok]

        header =
          Map.merge(if(ok_output == nil, do: %{}, else: ok_output), json_data[:input])
          |> Map.put(:slot, json_data[:pre_state][:tau])

        assert_expected_results(
          json_data,
          [
            :judgements,
            :core_reports,
            :timeslot,
            :curr_validators,
            :prev_validators
          ],
          file_name,
          extrinsic,
          header
        )
      end
    end)
  end
end
