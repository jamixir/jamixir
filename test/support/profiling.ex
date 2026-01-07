defmodule Test.Profiling do

  def setup do
    case System.get_env("PROFILE") do
      "cprof" -> setup_cprof()
      "eprof" -> setup_eprof()
      "fprof" -> setup_fprof()
      _ -> nil
    end
  end

  defp setup_cprof do
    Application.ensure_all_started(:runtime_tools)
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    :cprof.start()

    fn _ ->
      :cprof.stop()
      analyze_cprof(timestamp)
    end
  end

  defp setup_eprof do
    Application.ensure_all_started(:runtime_tools)
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    output_file = "eprof_analysis_#{timestamp}.txt"
    :eprof.start()
    :eprof.start_profiling([self()])

    fn _ ->
      :eprof.stop_profiling()
      analyze_eprof(output_file)
      :eprof.stop()
    end
  end

  defp setup_fprof do
    Application.ensure_all_started(:runtime_tools)
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    trace_file = "fprof_trace_#{timestamp}.trace"
    analysis_file = "fprof_analysis_#{timestamp}.txt"

    IO.puts("Starting fprof profiling (comprehensive call stack tracing)...")
    IO.puts("Trace file: #{trace_file}")
    IO.puts("Analysis file: #{analysis_file}")

    :fprof.start()
    :fprof.trace([:start, file: String.to_charlist(trace_file)])

    fn _ ->
      :fprof.trace(:stop)
      IO.puts("Processing trace file...")
      :fprof.profile(file: String.to_charlist(trace_file))

      :fprof.analyse(
        dest: String.to_charlist(analysis_file),
        sort: :acc,
        totals: false,
        details: true,
        callers: true
      )

      :fprof.stop()
      IO.puts("\nFprof profiling completed!")
      IO.puts("Trace file: #{trace_file}")
      IO.puts("Analysis file: #{analysis_file}")
    end
  end

  defp analyze_cprof(timestamp) do
    IO.puts("\n=== CPROF ANALYSIS ===")
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
        IO.puts("Function call counts (top 10 modules):")

        results
        |> Enum.take(10)
        |> Enum.each(fn {module, count, _functions} ->
          IO.puts("  #{module}: #{count} calls")
        end)

        IO.puts("\nDetailed analysis saved to: #{output_file}")
        IO.puts("\nCprof shows function call counts. Use eprof for timing information.")

      error ->
        IO.puts("Analysis result: #{inspect(error)}")
    end
  end

  defp analyze_eprof(output_file) do
    IO.puts("\n=== EPROF ANALYSIS ===")

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
        IO.puts("\n🔄 Processing eprof output to show top 20 bottlenecks...")
        {output, exit_code} = System.cmd(script_path, [output_file])

        if exit_code == 0 do
          IO.puts(String.trim(output))
        else
          IO.puts(:stderr, "❌ Error processing eprof output: #{output}")
        end
      else
        IO.puts("process_eprof.sh script not found - raw analysis saved to #{output_file}")
      end
    catch
      error ->
        IO.puts(:stderr, "Error during eprof analysis: #{inspect(error)}")
        IO.puts("Falling back to basic analysis...")
        :eprof.analyze()
    end
  end
end
