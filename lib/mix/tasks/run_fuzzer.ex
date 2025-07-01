defmodule Mix.Tasks.RunFuzzer do
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Application.put_env(:jamixir, :fuzzer_mode, true)
    Mix.Task.run("run", args)
  end
end
