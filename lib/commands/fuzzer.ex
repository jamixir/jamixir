defmodule Jamixir.Commands.Fuzzer do
  alias Util.Logger, as: Log

  @switches [
    socket_path: :string,
    log: :string,
    help: :boolean
  ]

  @aliases [
    h: :help
  ]

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    case args do
      [] ->
        print_help()

      ["--help"] ->
        print_help()

      ["-h"] ->
        print_help()

      _ ->
        start_fuzzer(opts)
    end
  end

  defp start_fuzzer(opts) do
    Log.info("🔧 Starting fuzzer mode")

    if log_level = opts[:log] do
      Log.info("Setting log level to #{log_level}")
      Logger.configure(level: :"#{log_level}")
    end

    Application.put_env(:jamixir, :fuzzer_mode, true)

    if socket_path = opts[:socket_path] do
      Application.put_env(:jamixir, :fuzzer_socket_path, socket_path)
    end

    run_args = []
    run_args = if opts[:log], do: ["--log", opts[:log]] ++ run_args, else: run_args
    run_args = if opts[:socket_path], do: ["--socket-path", opts[:socket_path]] ++ run_args, else: run_args

    Jamixir.Commands.Run.run(run_args)
  end

  defp print_help do
    IO.puts("""
    Run the fuzzer listener on unix domain socket

    Usage: jamixir fuzzer [OPTIONS]

    Options:
          --socket-path <PATH>       Unix domain socket path for fuzzer mode
          --log <LEVEL>              Log level (none | info | warninig | error | debug) default: info
      -h, --help                     Print help

    Examples:
      jamixir fuzzer --socket-path ./fuzzer.sock
      jamixir fuzzer --socket-path /tmp/jamixir_fuzzer.sock --log debug
      jamixir fuzzer --log warn --socket-path ./fuzzer.sock
    """)
  end
end
