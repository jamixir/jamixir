defmodule VectorTest do
  use ExUnit.Case, async: true
  alias Block.Header
  alias HTTPoison.Response
  alias GitHubRepoReader

  @owner "w3f"
  @repo "jamtestvectors"

  setup_all do
    files = GitHubRepoReader.fetch_repo_files(@owner, @repo)
    {:ok, files: files}
  end

  @tag :skip
  test "verify test vectors", %{files: files} do
    Enum.each(files, fn file ->
      if String.ends_with?(file, ".json") do
        {:ok, json_data} = fetch_and_parse_json(file, "master")
        assert_expected_results(json_data)
      end
    end)
  end

  defp fetch_and_parse_json(file, branch = "master") do
    url = "https://raw.githubusercontent.com/#{@owner}/#{@repo}/#{branch}/#{file}"
    headers = [{"User-Agent", "Elixir"}]

    case HTTPoison.get(url, headers) do
      {:ok, %Response{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %Response{status_code: status_code}} ->
        IO.puts("Failed to fetch file: HTTP #{status_code}")
        {:error, :failed_to_fetch}

      {:error, %HTTPoison.Error{reason: reason}} ->
        IO.puts("Failed to fetch file: #{reason}")
        {:error, :failed_to_fetch}
    end
  end

  defp assert_expected_results(json_data) do
    # Translate JSON data into your system modules and run assertions
    # Example:
    pre_state = System.State.from_json(json_data["pre_state"])
    header = %Header{timeslot: json_data["input"]["slot"]}
    new_state = System.State.add_block(pre_state, %Block{header: header})

    expected_state = System.State.from_json(json_data["post_state"])
    assert new_state == expected_state
  end
end
