defmodule Mix.Tasks.Cli do
  alias System.State
  use Mix.Task

  @shortdoc "Overrides the default `mix run` to start Jamixir.CLI"

  def run(_args) do
    IO.puts("starting...")
    state = State.from_genesis()
    # credo:disable-for-next-line
    IO.inspect(state)
    IO.puts("stopping...")
  end
end
