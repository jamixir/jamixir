defmodule Mix.Tasks.Cli do
  use Mix.Task
  @shortdoc "Run Jamixir CLI interface"

  def run(args) do
    Jamixir.main(args)
  end
end
