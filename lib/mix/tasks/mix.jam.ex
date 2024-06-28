defmodule Mix.Tasks.Jam do
  use Mix.Task

  @shortdoc "Overrides the default `mix run` to start Jamixir.CLI"
  
  def run(_args) do
    Jamixir.CLI.start()
  end
end