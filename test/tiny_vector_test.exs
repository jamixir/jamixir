defmodule ConstantsMock do
  def epoch_length, do: 12
  def ticket_submission_end, do: 10
end

defmodule LocalVectorTest do
  use ExUnit.Case
  import Mox
  require Logger
  setup :verify_on_exit!

  Application.put_env(:elixir, :ansi_enabled, true)

  @owner "w3f"
  @repo "jamtestvectors"
  @branch "master"
  @path "safrole/tiny"

  # ANSI color codes
  @blue IO.ANSI.blue()
  @green IO.ANSI.green()
  @yellow IO.ANSI.yellow()
  @red IO.ANSI.red()
  @cyan IO.ANSI.cyan()
  @bright IO.ANSI.bright()
  @reset IO.ANSI.reset()

  defp print_error(file_name, expected, received, status) do
    status_indicator = if status == :pass, do: "#{@green}✓", else: "#{@red}✗"

    IO.puts("""
    #{@bright}#{@cyan}#{file_name}#{@reset}
    #{@yellow}│#{@reset} #{status_indicator}#{@reset} errors: expected #{format_error(expected)} / received #{format_error(received)}
    """)
  end

  defp format_error("none"), do: "#{@blue}'none'#{@reset}"
  defp format_error(error), do: "#{@yellow}'#{error}'#{@reset}"

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
        {:ok, json_data} = fetch_and_parse_json(file_name)

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

  defp fetch_and_parse_json(file_name) do
    url =
      "https://raw.githubusercontent.com/#{@owner}/#{@repo}/#{@branch}/#{@path}/#{file_name}.json"

    headers = [{"User-Agent", "Elixir"}]

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        IO.puts("Failed to fetch file #{file_name}: HTTP #{status_code}")
        {:error, :failed_to_fetch}

      {:error, %HTTPoison.Error{reason: reason}} ->
        IO.puts("Failed to fetch file #{file_name}: #{reason}")
        {:error, :failed_to_fetch}
    end
  end

  defp assert_expected_results(json_data, tested_keys, file_name) do
    pre_state = System.State.from_json(json_data["pre_state"])
    block = Block.from_json(json_data)
    expected_state = System.State.from_json(json_data["post_state"])

    result =
      System.State.add_block(pre_state, block)

    case {result, Map.get(json_data["output"], "err")} do
      {{:ok, new_state}, nil} ->
        # No error expected, assert on the tested keys
        Enum.each(tested_keys, fn key ->
          assert Map.get(new_state, key) == Map.get(expected_state, key),
                 "Mismatch for key: #{key}"
        end)

      {{:ok, _}, error_expected} ->
        print_error(file_name, error_expected, "none", :fail)
        flunk("Expected error '#{error_expected}', but no error occurred")

      {{:error, _returned_state, reason}, nil} ->
        print_error(file_name, "none", reason, :fail)
        flunk("Expected no error, but received error: '#{reason}'")

      {{:error, returned_state, reason}, error_expected} ->
        print_error(file_name, error_expected, reason, :pass)

        Enum.each(tested_keys, fn key ->
          assert Map.get(returned_state, key) == Map.get(pre_state, key),
                 "State changed unexpectedly for key: #{key}"
        end)
    end
  end
end
