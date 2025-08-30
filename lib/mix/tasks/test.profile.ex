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
    mode = opts[:mode] || "eflame"
    timestamp = DateTime.utc_now() |> DateTime.to_unix()

    case mode do
      "cprof" ->
        run_cprof(test_args, timestamp)

      "eprof" ->
        run_eprof(test_args, timestamp)

      "fprof" ->
        run_fprof(test_args, timestamp)



      _ ->
        Mix.shell().error("Unknown mode: #{mode}")
        Mix.shell().info("Available modes: cprof, eprof, fprof,")
    end
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

  defp run_cprof(test_args, timestamp) do
    Mix.shell().info("Starting cprof profiling (function call counts)...")

    :cprof.start()

    try do
      result = Mix.Task.run("test", test_args)
      Mix.shell().info("Test completed: #{inspect(result)}")

      Mix.shell().info("\n=== CPROF ANALYSIS ===")
      analysis = :cprof.analyse()

      output_file = "cprof_analysis_#{timestamp}.txt"

      case analysis do
        {total_calls, results} when is_list(results) ->
          content =
            ["=== CPROF ANALYSIS ===\n", "Total calls: #{total_calls}\n\n"] ++
              Enum.map(results, fn {module, count, functions} ->
                module_info = "#{module}: #{count} total calls\n"

                function_info =
                  Enum.map(functions, fn {{_module, function, arity}, count} ->
                    "  #{function}/#{arity}: #{count} calls"
                  end)
                  |> Enum.join("\n")

                module_info <> function_info <> "\n"
              end)

          File.write!(output_file, Enum.join(content, "\n"))

          # Display top 10 modules summary
          Mix.shell().info("Function call counts (top 10 modules):")

          results
          |> Enum.take(10)
          |> Enum.each(fn {module, count, _functions} ->
            Mix.shell().info("  #{module}: #{count} calls")
          end)

          Mix.shell().info("\nDetailed analysis saved to: #{output_file}")

        error ->
          Mix.shell().info("Analysis result: #{inspect(error)}")
      end
    after
      :cprof.stop()
    end

    Mix.shell().info("\nCprof shows function call counts. Use eprof for timing information.")
  end

  defp run_eprof(test_args, timestamp) do
    Mix.shell().info("Starting eprof profiling (function timing)...")

    output_file = "eprof_analysis_#{timestamp}.txt"

    :eprof.start()
    :eprof.start_profiling([self()])

    try do
      result = Mix.Task.run("test", test_args)
      Mix.shell().info("Test completed: #{inspect(result)}")
    after
      :eprof.stop_profiling()
      Mix.shell().info("\n=== EPROF ANALYSIS ===")

      # Use eprof:log/1 to write output to file and analyze with filtering
      try do
        :eprof.log(String.to_charlist(output_file))

        top_time_filter = [
          {:filter,
           [

             {:time, 1.0}
           ]},
          {:sort, :time}
        ]

        :eprof.analyze(:total, top_time_filter)

        script_path = Path.join(File.cwd!(), "process_eprof.sh")

        if File.exists?(script_path) do
          Mix.shell().info("\n🔄 Processing eprof output to show top 20 bottlenecks...")
          {output, exit_code} = System.cmd(script_path, [output_file])

          if exit_code == 0 do
            Mix.shell().info(String.trim(output))
          else
            Mix.shell().error("❌ Error processing eprof output: #{output}")
          end
        else
          Mix.shell().info(
            "process_eprof.sh script not found - raw analysis saved to #{output_file}"
          )
        end
      catch
        error ->
          Mix.shell().error("Error during eprof analysis: #{inspect(error)}")
          Mix.shell().info("Falling back to basic analysis...")
          :eprof.analyze()
      end

      :eprof.stop()
    end
  end

  defp run_fprof(test_args, timestamp) do
    trace_file = "fprof_trace_#{timestamp}.trace"
    analysis_file = "fprof_analysis_#{timestamp}.txt"
    summary_file = "fprof_summary_#{timestamp}.txt"

    Mix.shell().info("Starting fprof profiling (comprehensive call stack tracing)...")
    Mix.shell().info("Trace file: #{trace_file}")
    Mix.shell().info("Analysis file: #{analysis_file}")

    :fprof.start()
    :fprof.trace([:start, file: String.to_charlist(trace_file)])

    try do
      result = Mix.Task.run("test", test_args)
      Mix.shell().info("Test completed: #{inspect(result)}")
    after
      :fprof.trace(:stop)
      Mix.shell().info("Processing trace file...")
      :fprof.profile(file: String.to_charlist(trace_file))

      :fprof.analyse([
        dest: String.to_charlist(analysis_file),
        sort: :acc,
        totals: false,
        details: true,
        callers: true
      ])

      :fprof.stop()


    end

    Mix.shell().info("\nFprof profiling completed!")

  end


end
