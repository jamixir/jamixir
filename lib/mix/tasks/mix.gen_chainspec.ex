defmodule Mix.Tasks.GenChainspec do
  use Mix.Task

  @shortdoc "Generates chainspec files from genesis.json"

  def run(args) do
    # Reuse the same logic as the release command
    Jamixir.Commands.GenChainspec.run(args)
  end
end
