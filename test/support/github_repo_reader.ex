defmodule GitHubRepoReader do
  @moduledoc """
  A module to read all files from a GitHub repository.
  """

  @github_api "https://api.github.com"

  def fetch_repo_files(owner, repo) do
    fetch_files_recursive(owner, repo, "")
  end

  defp fetch_files_recursive(owner, repo, path) do
    url = "#{@github_api}/repos/#{owner}/#{repo}/contents/#{path}"
    headers = [{"User-Agent", "Elixir"}]

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body
        |> Jason.decode!()
        |> Enum.flat_map(fn
          %{"type" => "file", "path" => file_path} -> [file_path]
          %{"type" => "dir", "path" => dir_path} -> fetch_files_recursive(owner, repo, dir_path)
          _ -> []
        end)

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        IO.puts("Failed to fetch files: HTTP #{status_code}")
        []

      {:error, %HTTPoison.Error{reason: reason}} ->
        IO.puts("Failed to fetch files: #{reason}")
        []
    end
  end
end
