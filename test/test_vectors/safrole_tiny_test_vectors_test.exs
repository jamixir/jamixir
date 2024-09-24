defmodule ConstantsMock do
  def epoch_length, do: 12
  def ticket_submission_end, do: 10
end

defmodule SafroleTinyTestVectors do
  use ExUnit.Case
  import Mox
  import TestVectorUtil
  setup :verify_on_exit!

  @path "safrole/tiny"

  setup_all do
    RingVrf.init_ring_context(6)
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    Application.put_env(:jamixir, Constants, ConstantsMock)

    Application.put_env(:jamixir, :original_modules, [
      System.State.Safrole,
      System.Validators.Safrole,
      Block.Extrinsic.TicketProof
    ])

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.delete_env(:jamixir, Constants)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  describe "test vectors" do
    test "verify epoch length" do
      assert Constants.epoch_length() == 12
    end

    @tag :tiny_test_vectors
    test "verify test vectors from GitHub" do
      files_to_test = [
        "enact-epoch-change-with-no-tickets-1",
        "enact-epoch-change-with-no-tickets-2",
        "enact-epoch-change-with-no-tickets-3",
        "enact-epoch-change-with-no-tickets-4",
        "publish-tickets-no-mark-1",
        "publish-tickets-no-mark-2",
        "publish-tickets-no-mark-3",
        "publish-tickets-no-mark-4",
        "publish-tickets-no-mark-5",
        "publish-tickets-no-mark-6",
        "publish-tickets-no-mark-7",
        "publish-tickets-no-mark-8",
        "publish-tickets-no-mark-9",
        "publish-tickets-with-mark-1",
        "publish-tickets-with-mark-2",
        "publish-tickets-with-mark-3",
        "publish-tickets-with-mark-4",
        "publish-tickets-with-mark-5",
        "skip-epoch-tail-1",
        "skip-epochs-1"
      ]

      Enum.each(files_to_test, fn file_name ->
        {:ok, json_data} = fetch_and_parse_json(file_name, @path)

        HeaderSealMock
        |> stub(:do_validate_header_seals, fn _, _, _, _ ->
          {:ok, %{vrf_signature_output: json_data["input"]["entropy"] |> Utils.hex_to_binary()}}
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
      end)
    end
  end
end
