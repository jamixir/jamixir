defmodule Jamixir.DBCase do
  @moduledoc """
  A test case module that sets up database sandbox with proper process allowances.

  Use this module in tests that need database access from spawned processes
  (like GenServers).

  ## Usage

      use Jamixir.DBCase

  Or with async (not recommended when sharing connections with GenServers):

      use Jamixir.DBCase, async: true
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Jamixir.DBCase
    end
  end

  setup tags do
    :ok = Sandbox.checkout(Jamixir.Repo)

    unless tags[:async] do
      Sandbox.mode(Jamixir.Repo, {:shared, self()})
    end

    :ok
  end

  @doc """
  Allows a process to use the test's database connection.
  Use this when you need to allow a specific GenServer process.
  """
  def allow_db_access(pid) when is_pid(pid) do
    Sandbox.allow(Jamixir.Repo, self(), pid)
  end

  def allow_db_access(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> {:error, :process_not_found}
      pid -> allow_db_access(pid)
    end
  end
end
