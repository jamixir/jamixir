defmodule Mix.Tasks.Jam do
  use Mix.Task
  require Logger
  @shortdoc "Overrides the default `mix run` to start Jamixir.CLI"

  def run(args) do
    # Reuse the same logic as the release command
    Jamixir.Commands.Run.run(args)
  end
end
