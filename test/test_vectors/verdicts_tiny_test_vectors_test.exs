defmodule VerdictsConstantsMock do
  def epoch_length, do: 12
  def ticket_submission_end, do: 10
end

defmodule VerdictsTinyTestVectors do
  use ExUnit.Case, async: false
  import Mox
  import TestVectorUtil
  setup :verify_on_exit!

  @path "local_vectors/disputes"

  setup_all do
    RingVrf.init_ring_context(6)
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    Application.put_env(:jamixir, Constants, VerdictsConstantsMock)

    Application.put_env(:jamixir, :original_modules, [
      System.State.Judgements,
      Block.Extrinsic.Disputes,
      Block.Extrinsic.Disputes.Culprit,
      Block.Extrinsic.Disputes.Fault,
      Block.Extrinsic.Disputes.Judgement,
      Block.Extrinsic.Disputes.Verdict
    ])

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.delete_env(:jamixir, Constants)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  describe "vectors" do
    test "verify epoch length" do
      assert Constants.epoch_length() == 12
    end

    files_to_test = [
      "progress_invalidates_avail_assignments-1"
    ]

    Enum.each(files_to_test, fn file_name ->
      @tag file_name: file_name
      @tag :tiny_test_vectors
      test "verify tiny test vectors #{file_name}", %{file_name: file_name} do
        {:ok, json_data} = fetch_and_parse_local_json(file_name <> ".json", @path)

        HeaderSealMock
        |> stub(:do_validate_header_seals, fn _, _, _, _ ->
          {:ok, %{vrf_signature_output: json_data[:input][:entropy] |> JsonDecoder.from_json()}}
        end)

        assert_expected_results(
          json_data,
          [
            :timeslot,
            :entropy_pool,
            :prev_validators,
            :curr_validators,
            :safrole
          ],
          file_name
        )
      end
    end)
  end
end
