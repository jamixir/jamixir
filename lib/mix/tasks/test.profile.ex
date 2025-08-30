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
  * `eflame` - Flame graphs (high overhead, visual flame graphs)

  ## Examples

      # Quick function call counts
      mix test.profile --mode cprof test/my_test.exs

      # Function timing analysis
      mix test.profile --mode eprof test/my_test.exs

      # Detailed trace for flame graphs
      mix test.profile --mode fprof test/my_test.exs

      # Visual flame graphs (default)
      mix test.profile test/my_test.exs
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

      "eflame" ->
        run_eflame(test_args, timestamp)

      _ ->
        Mix.shell().error("Unknown mode: #{mode}")
        Mix.shell().info("Available modes: cprof, eprof, fprof, eflame")
    end
  end

  defp parse_args(args) do
    # Find the --mode option and its value
    mode_index = Enum.find_index(args, fn arg -> arg == "--mode" end)

    if mode_index do
      mode_value = Enum.at(args, mode_index + 1)
      # Everything before --mode and after mode value becomes test args
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

      # Analyze all modules
      Mix.shell().info("\n=== CPROF ANALYSIS ===")
      analysis = :cprof.analyse()

      # Save analysis to file and display summary
      output_file = "cprof_analysis_#{timestamp}.txt"

      case analysis do
        {total_calls, results} when is_list(results) ->
          # Write detailed analysis to file
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
             # Functions taking ≥0.1% of total time
             {:time, 1.0}
           ]},
          # Sort by time percentage (lowest first)
          {:sort, :time}
        ]

        :eprof.analyze(:total, top_time_filter)

        # Automatically process the eprof file to show only top 20 bottlenecks
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
            "📋 process_eprof.sh script not found - raw analysis saved to #{output_file}"
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
    output_file = "test_profile_#{timestamp}.fprof"
    analysis_file = "test_profile_#{timestamp}.analysis"
    summary_file = "fprof_summary_#{timestamp}.txt"

    Mix.shell().info("Starting fprof profiling (comprehensive tracing)...")
    Mix.shell().info("Output: #{output_file}, Analysis: #{analysis_file}")

    :fprof.start()
    :fprof.trace([:start, file: String.to_charlist(output_file)])

    try do
      result = Mix.Task.run("test", test_args)
      Mix.shell().info("Test completed: #{inspect(result)}")
    after
      :fprof.trace(:stop)
      :fprof.profile(file: String.to_charlist(output_file))
      :fprof.analyse(dest: String.to_charlist(analysis_file))
      :fprof.stop()

      # Create a human-readable summary
      Mix.shell().info("\n=== FPROF SUMMARY ===")
      Mix.shell().info("Trace file: #{output_file}")
      Mix.shell().info("Analysis file: #{analysis_file}")
      Mix.shell().info("Summary file: #{summary_file}")

      # Write summary info to file
      summary_content = [
        "=== FPROF PROFILING SUMMARY ===",
        "Timestamp: #{timestamp}",
        "Trace file: #{output_file}",
        "Analysis file: #{analysis_file}",
        "",
        "To view the analysis:",
        "1. View raw analysis: cat #{analysis_file}",
        "2. Convert to KCachegrind format: erlgrind #{output_file}",
        "3. Open with KCachegrind or similar tools",
        "",
        "Note: fprof generates detailed call graphs with timing information.",
        "Use this for comprehensive performance analysis."
      ]

      File.write!(summary_file, Enum.join(summary_content, "\n"))
    end

    Mix.shell().info("\nFprof profiling completed!")
    Mix.shell().info("Use erlgrind to convert to KCachegrind format:")
    Mix.shell().info("  erlgrind #{output_file}")
  end

  defp run_eflame(test_args, timestamp) do
    Application.ensure_all_started(:eflame)

    output_file = "test_profile_#{timestamp}"

    Mix.shell().info("Starting eflame profiling (flame graphs)...")
    Mix.shell().info("Output file: #{output_file}.out")
    Mix.shell().info("Note: Long-running tests may generate large trace files")

    try do
      result =
        :eflame.apply(:normal_with_children, output_file, Mix.Task, :run, ["test", test_args])

      Mix.shell().info("Profiling completed: #{inspect(result)}")
    catch
      :exit, {:timeout, _} ->
        Mix.shell().error("Profiling timed out - try a smaller test or use fprof mode")
        Mix.shell().info("  mix test.profile --mode fprof #{Enum.join(test_args, " ")}")

      error ->
        Mix.shell().error("Error during profiling: #{inspect(error)}")
        Mix.shell().info("Try using eprof mode for simpler profiling:")
        Mix.shell().info("  mix test.profile --mode eprof #{Enum.join(test_args, " ")}")
    end

    output_path = "#{output_file}.out"

    if File.exists?(output_path) do
      file_size = File.stat!(output_path).size
      Mix.shell().info("Flame graph data saved to: #{output_path} (#{file_size} bytes)")

      if file_size > 0 do
        Mix.shell().info("Upload to https://www.speedscope.app/ to view the flame graph")
      end
    else
      Mix.shell().error("Output file #{output_path} was not created")
    end
  end
end
