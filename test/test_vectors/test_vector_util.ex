defmodule TestVectorUtil do
  use ExUnit.Case
  Application.put_env(:elixir, :ansi_enabled, true)

  @owner "w3f"
  @repo "jamtestvectors"
  @branch "master"

  # ANSI color codes
  @blue IO.ANSI.blue()
  @green IO.ANSI.green()
  @yellow IO.ANSI.yellow()
  @red IO.ANSI.red()
  @cyan IO.ANSI.cyan()
  @bright IO.ANSI.bright()
  @reset IO.ANSI.reset()
  def print_error(file_name, expected, received, status) do
    status_indicator = if status == :pass, do: "#{@green}✓", else: "#{@red}✗"

    IO.puts("""
    #{@bright}#{@cyan}#{file_name}#{@reset}
    #{@yellow}│#{@reset} #{status_indicator}#{@reset} errors: expected #{format_error(expected)} / received #{format_error(received)}
    """)
  end

  def format_error("none"), do: "#{@blue}'none'#{@reset}"
  def format_error(error), do: "#{@yellow}'#{error}'#{@reset}"

  def fetch_and_parse_json(file_name, path) do
    url =
      "https://raw.githubusercontent.com/#{@owner}/#{@repo}/#{@branch}/#{path}/#{file_name}.json"

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

  def assert_expected_results(json_data, tested_keys, file_name) do
    pre_state = System.State.from_json(json_data["pre_state"])
    block = Block.from_json(json_data)
    expected_state = System.State.from_json(json_data["post_state"])

    result = System.State.add_block(pre_state, block)

    case {result, Map.get(json_data["output"], "err")} do
      {{:ok, state_}, nil} ->
        # No error expected, assert on the tested keys
        Enum.each(tested_keys, fn key ->
          assert Map.get(state_, key) == Map.get(expected_state, key),
                 "Mismatch for key: #{key} in test vector #{file_name}"
        end)

      {{:ok, _}, error_expected} ->
        print_error(file_name, error_expected, "none", :fail)
        flunk("Expected error '#{error_expected}', but no error occurred")

      {{:error, _returned_state, reason}, nil} ->
        print_error(file_name, "none", reason, :fail)
        flunk("Expected no error, but received error: '#{reason}'")

      {{:error, returned_state, _reason}, _error_expected} ->
        # print_error(file_name, error_expected, reason, :pass)

        Enum.each(tested_keys, fn key ->
          assert Map.get(returned_state, key) == Map.get(pre_state, key),
                 "State changed unexpectedly for key: #{key}"
        end)
    end

    :ok
  end
end
