defmodule Jamixir.Commands.Run do
  @moduledoc """
  Run a Jamixir node
  """
  require Logger

  @switches [
    keys: :string,
    genesis: :string,
    port: :integer,
    help: :boolean
  ]

  @aliases [
    h: :help
  ]

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    if opts[:help] do
      print_help()
    else
      start_node(opts)
    end
  end

  defp start_node(opts) do
    # Reuse exact logic from Mix.Tasks.Jam
    Logger.info("🟣 Pump up the JAM, pump it up...")
    Logger.info("System loaded with config: #{inspect(Jamixir.config())}")

    if keys_file = opts[:keys] do
      KeyManager.load_keys(keys_file)
    end

    if genesis_file = opts[:genesis] do
      Application.put_env(:jamixir, :genesis_file, genesis_file)
    end

    if port = opts[:port] do
      Application.put_env(:jamixir, :port, port)
    end

    Application.ensure_all_started(:jamixir)
    Process.sleep(:infinity)
  end

  defp print_help do
    IO.puts("""
    Run a Jamixir node

    Usage: jamixir run [OPTIONS]

    Options:
          --keys <KEYS>        Keys file to load
          --genesis <GENESIS>  Genesis file to use
          --port <PORT>        Port to listen on
      -h, --help               Print help
    """)
  end
end
