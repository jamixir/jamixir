defmodule ConstantsMock do
  def epoch_length, do: 12
  def ticket_submission_end, do: 10
end

defmodule SafroleTests do
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
end

defmodule SafroleTinyTestVectors do
  use ExUnit.Case, async: false
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

  describe "vectors" do
    test "verify epoch length" do
      assert Constants.epoch_length() == 12
    end

    Enum.each(SafroleTests.files(), fn file_name ->
      @tag file_name: file_name
      @tag :tiny_test_vectors
      test "verify tiny test vectors #{file_name}", %{file_name: file_name} do
        {:ok, json_data} = fetch_and_parse_json(file_name <> ".json", @path)

        stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
          {:ok, %{vrf_signature_output: json_data[:input][:entropy] |> JsonDecoder.from_json()}}
        end)

        assert_expected_results(
          json_data,
          SafroleTests.tested_keys(),
          file_name
        )
      end
    end)
  end
end
