defmodule GitHubRepoReader do
  @moduledoc """
  A module to read all files from a GitHub repository with caching.
  """

  @github_api "https://api.github.com"
  @cache_file "test_vectors.etf"

  def fetch_repo_files(owner, repo) do
    case read_cache() do
      {:ok, cache} ->
        case cache[{owner, repo}] do
          nil -> fetch_and_cache_files(owner, repo)
          files -> files
        end

      :error ->
        fetch_and_cache_files(owner, repo)
    end
  end

  defp fetch_and_cache_files(owner, repo) do
    files = fetch_files_recursive(owner, repo, "")

    cache =
      case read_cache() do
        {:ok, existing_cache} -> existing_cache
        :error -> %{}
      end

    updated_cache = Map.put(cache, {owner, repo}, files)
    write_cache(updated_cache)
    files
  end

  defp fetch_files_recursive(owner, repo, path) do
    url = "#{@github_api}/repos/#{owner}/#{repo}/contents/#{path}"
    headers = [{"User-Agent", "Elixir 2"}]

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

  defp read_cache do
    case File.read(@cache_file) do
      {:ok, binary} -> {:ok, :erlang.binary_to_term(binary)}
      {:error, _} -> :error
    end
  end

  defp write_cache(cache) do
    binary = :erlang.term_to_binary(cache)
    File.write!(@cache_file, binary)
  end
end
