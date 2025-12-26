defmodule Jamixir.Release do
  @moduledoc """
  Tasks for running migrations in release mode.

  This module provides functions to create the database and run migrations
  when the application is deployed as a release (where Mix is not available).

  Usage from release:
    bin/jamixir eval "Jamixir.Release.migrate()"

  Or it can be called automatically at application startup.
  """

  @app :jamixir

  def migrate do
    load_app()
    ensure_database_created()
    run_migrations()
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp load_app do
    Application.load(@app)
  end

  defp ensure_database_created do
    for repo <- repos() do
      case repo.__adapter__().storage_up(repo.config()) do
        :ok ->
          IO.puts("Database created for #{inspect(repo)}")

        {:error, :already_up} ->
          IO.puts("Database already exists for #{inspect(repo)}")

        {:error, reason} ->
          IO.puts("Could not create database for #{inspect(repo)}: #{inspect(reason)}")
      end
    end
  end

  defp run_migrations do
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end
end
