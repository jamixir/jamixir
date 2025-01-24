defmodule Mix.Tasks.Jam do
  use Mix.Task

  @shortdoc "Overrides the default `mix run` to start Jamixir.CLI"

  def run(_args) do
    IO.puts("🟣 Pump up the JAM, pump it up...")
    Application.ensure_all_started(:jamixir)
    Process.sleep(:infinity)

    # Jamixir.start(nil, nil)
  end
end
