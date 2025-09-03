defmodule PVM.MemoryProfiler do


  use Agent
  require Logger

  defstruct [
    :started_at,
    :ended_at,
    :total_check_access_calls,
    :total_set_access_calls,
    :total_read_calls,
    :total_write_calls,
    :successful_reads,
    :successful_writes,
    :check_access_by_type,
    :set_access_by_type,
    :read_bytes_total,
    :write_bytes_total,
    :function_times
  ]

  def start_link(_opts) do
    Agent.start_link(fn ->
      %__MODULE__{
        started_at: System.monotonic_time(:millisecond),
        total_check_access_calls: 0,
        total_set_access_calls: 0,
        total_read_calls: 0,
        total_write_calls: 0,
        successful_reads: 0,
        successful_writes: 0,
        check_access_by_type: %{read: 0, write: 0},
        set_access_by_type: %{read: 0, write: 0},
        read_bytes_total: 0,
        write_bytes_total: 0,
        function_times: %{
          check_access: {0, 0}, # {total_time_microseconds, call_count}
          set_access: {0, 0},
          read: {0, 0},
          write: {0, 0}
        }
      }
    end, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :transient
    }
  end

  def reset() do
    Agent.update(__MODULE__, fn _state ->
      %__MODULE__{
        started_at: System.monotonic_time(:millisecond),
        total_check_access_calls: 0,
        total_set_access_calls: 0,
        total_read_calls: 0,
        total_write_calls: 0,
        successful_reads: 0,
        successful_writes: 0,
        check_access_by_type: %{read: 0, write: 0},
        set_access_by_type: %{read: 0, write: 0},
        read_bytes_total: 0,
        write_bytes_total: 0,
        function_times: %{
          check_access: {0, 0},
          set_access: {0, 0},
          read: {0, 0},
          write: {0, 0}
        }
      }
    end)
  end

  def start_profiling() do
    reset()
    Logger.info("Memory profiling started")
  end

  def stop_profiling() do
    Agent.update(__MODULE__, fn state ->
      %{state | ended_at: System.monotonic_time(:millisecond)}
    end)
    Logger.info("Memory profiling stopped")
  end

  def record_check_access(access_type, execution_time_microseconds) do
    Agent.update(__MODULE__, fn state ->
      {prev_time, prev_count} = state.function_times.check_access

      %{state |
        total_check_access_calls: state.total_check_access_calls + 1,
        check_access_by_type: Map.update!(state.check_access_by_type, access_type, &(&1 + 1)),
        function_times: %{state.function_times |
          check_access: {prev_time + execution_time_microseconds, prev_count + 1}
        }
      }
    end)
  end

  def record_set_access(access_type, execution_time_microseconds) do
    Agent.update(__MODULE__, fn state ->
      {prev_time, prev_count} = state.function_times.set_access

      %{state |
        total_set_access_calls: state.total_set_access_calls + 1,
        set_access_by_type: Map.update!(state.set_access_by_type, access_type, &(&1 + 1)),
        function_times: %{state.function_times |
          set_access: {prev_time + execution_time_microseconds, prev_count + 1}
        }
      }
    end)
  end

  def record_read(success, bytes_read, execution_time_microseconds) do
    Agent.update(__MODULE__, fn state ->
      {prev_time, prev_count} = state.function_times.read

      %{state |
        total_read_calls: state.total_read_calls + 1,
        successful_reads: if(success, do: state.successful_reads + 1, else: state.successful_reads),
        read_bytes_total: state.read_bytes_total + bytes_read,
        function_times: %{state.function_times |
          read: {prev_time + execution_time_microseconds, prev_count + 1}
        }
      }
    end)
  end

  def record_write(success, bytes_written, execution_time_microseconds) do
    Agent.update(__MODULE__, fn state ->
      {prev_time, prev_count} = state.function_times.write

      %{state |
        total_write_calls: state.total_write_calls + 1,
        successful_writes: if(success, do: state.successful_writes + 1, else: state.successful_writes),
        write_bytes_total: state.write_bytes_total + bytes_written,
        function_times: %{state.function_times |
          write: {prev_time + execution_time_microseconds, prev_count + 1}
        }
      }
    end)
  end

  def get_stats() do
    Agent.get(__MODULE__, & &1)
  end

  def print_stats() do
    stats = get_stats()

    total_duration_ms = case stats.ended_at do
      nil -> System.monotonic_time(:millisecond) - stats.started_at
      ended_at -> ended_at - stats.started_at
    end

    total_rw_requests = stats.total_read_calls + stats.total_write_calls

    Logger.info("=" <> String.duplicate("=", 60))
    Logger.info("🔍 MEMORY PROFILING RESULTS")
    Logger.info("=" <> String.duplicate("=", 60))
    Logger.info("⏱️  Total execution time: #{total_duration_ms}ms")
    Logger.info("")

    # Access checks
    Logger.info("ACCESS CHECKS")
    Logger.info("   Total check_access calls: #{stats.total_check_access_calls}")
    Logger.info("   Read checks: #{stats.check_access_by_type.read}")
    Logger.info("   Write checks: #{stats.check_access_by_type.write}")

    {check_time, check_count} = stats.function_times.check_access
    if check_count > 0 do
      Logger.info("   Avg time per check: #{Float.round(check_time / check_count, 2)}μs")
      Logger.info("   Total time in checks: #{Float.round(check_time / 1000, 2)}ms (#{Float.round(check_time / 1000 / total_duration_ms * 100, 1)}%)")
    end
    Logger.info("")

    # Access sets
    Logger.info("ACCESS SETS")
    Logger.info("   Total set_access calls: #{stats.total_set_access_calls}")
    Logger.info("   Read sets: #{stats.set_access_by_type.read}")
    Logger.info("   Write sets: #{stats.set_access_by_type.write}")

    {set_time, set_count} = stats.function_times.set_access
    if set_count > 0 do
      Logger.info("   Avg time per set: #{Float.round(set_time / set_count, 2)}μs")
      Logger.info("   Total time in sets: #{Float.round(set_time / 1000, 2)}ms (#{Float.round(set_time / 1000 / total_duration_ms * 100, 1)}%)")
    end
    Logger.info("")

    # Reads
    Logger.info("MEMORY READS")
    Logger.info("   Total read calls: #{stats.total_read_calls}")
    Logger.info("   Successful reads: #{stats.successful_reads}")
    Logger.info("   Read success rate: #{if stats.total_read_calls > 0, do: Float.round(stats.successful_reads / stats.total_read_calls * 100, 1), else: 0}%")
    Logger.info("   Total bytes read: #{stats.read_bytes_total}")

    {read_time, read_count} = stats.function_times.read
    if read_count > 0 do
      Logger.info("   Avg time per read: #{Float.round(read_time / read_count, 2)}μs")
      Logger.info("   Total time in reads: #{Float.round(read_time / 1000, 2)}ms (#{Float.round(read_time / 1000 / total_duration_ms * 100, 1)}%)")
    end
    Logger.info("")

    # Writes
    Logger.info("MEMORY WRITES")
    Logger.info("   Total write calls: #{stats.total_write_calls}")
    Logger.info("   Successful writes: #{stats.successful_writes}")
    Logger.info("   Write success rate: #{if stats.total_write_calls > 0, do: Float.round(stats.successful_writes / stats.total_write_calls * 100, 1), else: 0}%")
    Logger.info("   Total bytes written: #{stats.write_bytes_total}")

    {write_time, write_count} = stats.function_times.write
    if write_count > 0 do
      Logger.info("   Avg time per write: #{Float.round(write_time / write_count, 2)}μs")
      Logger.info("   Total time in writes: #{Float.round(write_time / 1000, 2)}ms (#{Float.round(write_time / 1000 / total_duration_ms * 100, 1)}%)")
    end
    Logger.info("")

    # Overall read/write percentages
    if total_rw_requests > 0 do
      read_percent = Float.round(stats.total_read_calls / total_rw_requests * 100, 1)
      write_percent = Float.round(stats.total_write_calls / total_rw_requests * 100, 1)

          Logger.info("READ/WRITE BREAKDOWN")
    Logger.info("   Total R/W requests: #{total_rw_requests}")
    Logger.info("   Read requests: #{stats.total_read_calls} (#{read_percent}%)")
    Logger.info("   Write requests: #{stats.total_write_calls} (#{write_percent}%)")
    Logger.info("")
    end

    # Additional analysis
    Logger.info("MEMORY ANALYSIS")
    total_memory_time_ms = (read_time + write_time + check_time + set_time) / 1000
    memory_percentage = if total_duration_ms > 0, do: Float.round(total_memory_time_ms / total_duration_ms * 100, 1), else: 0
    Logger.info("   Total time in memory operations: #{Float.round(total_memory_time_ms, 2)}ms (#{memory_percentage}%)")

    if stats.total_read_calls > 0 do
      avg_read_bytes = Float.round(stats.read_bytes_total / stats.total_read_calls, 1)
      Logger.info("   Average bytes per read: #{avg_read_bytes}")
    end

    if stats.total_write_calls > 0 do
      avg_write_bytes = Float.round(stats.write_bytes_total / stats.total_write_calls, 1)
      Logger.info("   Average bytes per write: #{avg_write_bytes}")
    end

    # Access check analysis
    check_to_operation_ratio = if total_rw_requests > 0, do: Float.round(stats.total_check_access_calls / total_rw_requests * 100, 1), else: 0
    Logger.info("   Access checks per operation: #{Float.round(stats.total_check_access_calls / max(total_rw_requests, 1), 2)} (#{check_to_operation_ratio}% overhead)")

    # Performance insights
    if stats.total_read_calls > 0 and stats.total_write_calls > 0 do
      {read_avg_time, _} = stats.function_times.read
      {write_avg_time, _} = stats.function_times.write
      read_avg = read_avg_time / stats.total_read_calls
      write_avg = write_avg_time / stats.total_write_calls
      write_slowdown = Float.round(write_avg / read_avg * 100 - 100, 1)
      Logger.info("   Write operations are #{write_slowdown}% slower than reads")
    end

    # Memory throughput
    total_bytes = stats.read_bytes_total + stats.write_bytes_total
    throughput_mb_s = if total_duration_ms > 0, do: Float.round(total_bytes / 1024 / 1024 / (total_duration_ms / 1000), 2), else: 0
    Logger.info("   Memory throughput: #{throughput_mb_s} MB/s")
    Logger.info("")

    Logger.info("=" <> String.duplicate("=", 60))
  end

  # Check if profiling is enabled
  def enabled?() do
    case Process.whereis(__MODULE__) do
      nil -> false
      _ -> true
    end
  end
end
