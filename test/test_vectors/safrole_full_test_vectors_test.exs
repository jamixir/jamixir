defmodule SafroleFullTestVectors do
  use ExUnit.Case
  import Mox
  import TestVectorUtil
  setup :verify_on_exit!
  @moduletag :full_vectorss

  @path "safrole/full"

  setup_all do
    RingVrf.init_ring_context(1023)
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)

    Application.put_env(:jamixir, :original_modules, [
      System.State.Safrole,
      System.Validators.Safrole,
      Block.Extrinsic.TicketProof,
    ])

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  describe "vectors" do
    test "verify epoch length" do
      assert Constants.epoch_length() == 600
    end

    files_to_test = [
      # "enact-epoch-change-with-no-tickets-1",
      "enact-epoch-change-with-no-tickets-2",
      # "enact-epoch-change-with-no-tickets-3",
      # "enact-epoch-change-with-no-tickets-4",
      # "publish-tickets-no-mark-1",
      # "publish-tickets-no-mark-2",
      # "publish-tickets-no-mark-3",
      # "publish-tickets-no-mark-4",
      # "publish-tickets-no-mark-5",
      # "publish-tickets-no-mark-6",
      # "publish-tickets-no-mark-7",
      # "publish-tickets-no-mark-8",
      # "publish-tickets-no-mark-9",
      # "publish-tickets-with-mark-1",
      # "publish-tickets-with-mark-2",
      # "publish-tickets-with-mark-3",
      # "publish-tickets-with-mark-4",
      # "publish-tickets-with-mark-5",
      # "skip-epoch-tail-1",
      # "skip-epochs-1"
    ]

    Enum.each(files_to_test, fn file_name ->
      @tag file_name: file_name
      test "verify full test vectors #{file_name}", %{file_name: file_name} do
        {:ok, json_data} = fetch_and_parse_json(file_name <> ".json", @path)

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
