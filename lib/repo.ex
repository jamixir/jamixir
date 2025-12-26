defmodule Jamixir.Repo do
  use Ecto.Repo,
    otp_app: :jamixir,
    adapter: Ecto.Adapters.SQLite3

  def init(_type, config) do
    # Handle runtime database path configuration
    config = resolve_database_path(config)
    {:ok, config}
  end

  defp resolve_database_path(config) do
    case Keyword.get(config, :database) do
      {:system, env_var, default} ->
        db_path = System.get_env(env_var) || default_db_path(default)
        ensure_db_directory(db_path)
        Keyword.put(config, :database, db_path)

      path when is_binary(path) ->
        ensure_db_directory(path)
        config

      _ ->
        config
    end
  end

  defp default_db_path(default) do
    # In release mode, use a path inside priv directory
    # Otherwise use the provided default
    case :code.priv_dir(:jamixir) do
      {:error, _} ->
        default

      priv_dir ->
        Path.join([priv_dir, "data", "jamixir.db"])
    end
  end

  defp ensure_db_directory(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end
end
