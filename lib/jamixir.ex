defmodule Jamixir do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Define workers and child supervisors to be supervised
      # {YourWorker, arg},
      # {YourSupervisor, arg}
    ]

    opts = [strategy: :one_for_one, name: Jamixir.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config do
    Application.get_env(:jamixir, Jamixir)
  end
end
