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
    # Check for command-line override first
    case Application.get_env(:jamixir, :database_path) do
      path when is_binary(path) ->
        # CLI override
        validate_database_path(path)
        ensure_db_directory(path)
        Keyword.put(config, :database, path)

      nil ->
        # Fall back to environment config
        case Keyword.get(config, :database) do
          {:system, env_var, default} ->
            db_path =
              if env_path = System.get_env(env_var) do
                validate_database_path(env_path)
                node_specific_db_path(env_path)
              else
                validate_database_path(default)
                node_specific_db_path(default)
              end

            ensure_db_directory(db_path)
            Keyword.put(config, :database, db_path)

          path when is_binary(path) ->
            validate_database_path(path)
            db_path = node_specific_db_path(path)
            ensure_db_directory(db_path)
            Keyword.put(config, :database, db_path)
        end
    end
  end

  defp node_specific_db_path(default) do
    # In test environments, use the default path as-is
    # In production/release, use node-specific paths for storage isolation
    if Jamixir.config()[:test_env] do
      default
    else
      node_dir = Jamixir.NodeIdentity.node_dir()
      db_dir = Path.join(node_dir, "data")

      # Extract filename from default path or use "jamixir.db"
      filename =
        case Path.basename(default) do
          "" -> "jamixir.db"
          name -> name
        end

      Path.join(db_dir, filename)
    end
  end

  defp validate_database_path(path) do
    # Absolute paths break storage isolation guarantees
    # Reject them unless explicitly allowed via config
    if Path.type(path) == :absolute do
      raise """
      Absolute database paths are not allowed; they break storage isolation.
      Path attempted: #{path}
      Instead, use relative paths.
      """
    end
  end

  defp ensure_db_directory(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end
end
