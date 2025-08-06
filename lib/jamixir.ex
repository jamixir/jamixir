defmodule Jamixir do
  require Config
  use Application

  @impl true
  def start(_type, _args) do
    children = get_children()
    opts = [strategy: :one_for_one, name: Jamixir.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_children do
    cond do
      # Fuzzer mode takes precedence if explicitly enabled
      Application.get_env(:jamixir, :fuzzer_mode, false) ->
        fuzzer_children()

      # Test environment handling
      (Jamixir.config()[:test_env] || false) and
          not Application.get_env(:jamixir, :start_full_app, false) ->
        test_children()

      # Default production mode
      true ->
        production_children()
    end
  end

  defp fuzzer_children do
    persist_storage? = Jamixir.config()[:storage_persist] || false
    socket_path = Application.get_env(:jamixir, :fuzzer_socket_path) ||
                  System.get_env("SOCKET_PATH") ||
                  "/tmp/jamixir_fuzzer.sock"

    [
      {Storage, [persist: persist_storage?]},
      {Task.Supervisor, name: Fuzzer.TaskSupervisor},
      Supervisor.child_spec({Task, fn -> Jamixir.Fuzzer.Service.accept(socket_path) end},
        restart: :permanent
      )
    ]
  end

  defp test_children do
    Util.Logger.info("🔧 Running in test environment")
    persist_storage? = Jamixir.config()[:storage_persist] || false

    [
      {Storage, [persist: persist_storage?]},
      Network.ConnectionManager,
      Jamixir.TimeTicker
    ]
  end

  defp production_children do
    Util.Logger.info("🔧 Running in production environment")
    persist_storage? = Jamixir.config()[:storage_persist] || false
    port = Application.get_env(:jamixir, :port, 9999)

    [
      {Storage, [persist: persist_storage?]},
      Network.ConnectionManager,
      {Network.Listener, [port: port]},
      Jamixir.TimeTicker,
      {Task.Supervisor, name: Jamixir.TaskSupervisor},
      Jamixir.InitializationTask,
      {Jamixir.NodeStateServer, []}
    ]
  end

  @impl true
  def stop(_state) do
    try do
      Network.ConnectionManager.shutdown_all_connections()
      Process.sleep(100)
    rescue
      _ -> :ok
    end

    :ok
  end

  def config do
    Application.get_env(:jamixir, Jamixir)
  end

  def config(k), do: config()[k]

  # CLI command dispatcher for release
  def main(args \\ []) do
    # Only start minimal applications needed for CLI commands
    Application.ensure_all_started(:logger)
    Application.ensure_all_started(:crypto)

    case args do
      [] ->
        print_help()

      ["--help"] ->
        print_help()

      ["-h"] ->
        print_help()

      ["help"] ->
        print_help()

      ["--version"] ->
        print_version()

      ["-V"] ->
        print_version()

      ["gen-keys" | rest] ->
        Jamixir.Commands.GenKeys.run(rest)

      ["list-keys" | rest] ->
        Jamixir.Commands.ListKeys.run(rest)

      ["run" | rest] ->
        # Don't start the application here - let the run command handle it
        Jamixir.Commands.Run.run(rest)

      ["fuzzer" | rest] ->
        Application.put_env(:jamixir, :fuzzer_mode, true)
        Jamixir.Commands.Fuzzer.run(rest)

      [cmd | _] ->
        IO.puts("Unknown command: #{cmd}")
        print_help()
        System.halt(1)
    end
  end

  defp print_help do
    IO.puts("""
    Jamixir node

    Usage: jamixir [OPTIONS] <COMMAND>

    Commands:
      fuzzer     Run the fuzzer listener on unix domain socket
      gen-keys   Generate a new secret key seed and print the derived session keys
      list-keys  List all session keys we have the secret key for
      run        Run a Jamixir node
      help       Print this message or the help of the given subcommand(s)

    Options:
      -h, --help     Print help
      -V, --version  Print version
    """)
  end

  defp print_version do
    version = Application.spec(:jamixir, :vsn) || "unknown"
    IO.puts("jamixir #{version}")
  end
end
