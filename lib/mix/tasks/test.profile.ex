defmodule Mix.Tasks.Test.Profile do
  use Mix.Task

  @shortdoc "Run mix test under profiling (supports --mode cprof|eprof|fprof|eflame)"

  @moduledoc """
  Gradient profiling approach for Elixir tests:

  ## Usage

      mix test.profile [--mode MODE] [test args...]

  ## Modes

  * `cprof` - Fast function call counting (least overhead, good for quick overview)
  * `eprof` - Function call timing (medium overhead, shows time per function)
  * `fprof` - Comprehensive tracing (high overhead, detailed call graphs)


  ## Examples

      # Quick function call counts
      mix test.profile --mode cprof test/my_test.exs

      # Function timing analysis
      mix test.profile --mode eprof test/my_test.exs

      # Detailed trace
      mix test.profile --mode fprof test/my_test.exs

  """

  def run(args) do
    {opts, test_args} = parse_args(args)
    mode = opts[:mode] || "cprof"

    # Set PROFILE env var and let test_helper.exs handle initialization
    System.cmd(
      "mix",
      ["test"] ++ test_args,
      env: [{"PROFILE", mode}],
      into: IO.stream(:stdio, :line)
    )
  end

  defp parse_args(args) do
    mode_index = Enum.find_index(args, fn arg -> arg == "--mode" end)

    if mode_index do
      mode_value = Enum.at(args, mode_index + 1)

      test_args =
        args
        |> Enum.with_index()
        |> Enum.reject(fn {_, i} -> i == mode_index or i == mode_index + 1 end)
        |> Enum.map(fn {arg, _} -> arg end)

      {[mode: mode_value], test_args}
    else
      {[], args}
    end
  end
end
