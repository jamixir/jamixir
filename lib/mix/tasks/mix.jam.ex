defmodule Mix.Tasks.Jam do
  use Mix.Task
  require Logger
  alias Jamixir.Commands.Run
  @shortdoc "Overrides the default `mix run` to start Jamixir.CLI"

  def run(args) do
    Run.run(args)
  end
end
