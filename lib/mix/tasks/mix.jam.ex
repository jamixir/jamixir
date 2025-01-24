defmodule Mix.Tasks.Jam do
  use Mix.Task
  require Logger
  @shortdoc "Overrides the default `mix run` to start Jamixir.CLI"

  def run(_args) do
    Logger.info("🟣 Pump up the JAM, pump it up...")
    Application.ensure_all_started(:jamixir)
    Process.sleep(:infinity)
  end
end
