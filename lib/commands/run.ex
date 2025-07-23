defmodule Jamixir.Commands.Run do
  @moduledoc """
  Run a Jamixir node
  """
  alias Util.Logger, as: Log

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
    Log.info("🟣 Pump up the JAM, pump it up...")
    Log.debug("System loaded with config: #{inspect(Jamixir.config())}")

    if keys_file = opts[:keys] do
      KeyManager.load_keys(keys_file)
    end

    if genesis_file = opts[:genesis] do
      Application.put_env(:jamixir, :genesis_file, genesis_file)
    end

    if port = opts[:port] do
      Application.put_env(:jamixir, :port, port)
    end

    Log.info("🎭 Starting as validator")

    Application.ensure_all_started(:jamixir)

    # Register this process so we can send it shutdown messages
    Process.register(self(), :shutdown_handler)

    # Spawn a simple input listener for  graceful shutdown
    spawn(fn -> input_listener() end)

    Log.info("Node running. Type 'q' + Enter for graceful shutdown")

    # Wait for shutdown message or sleep forever
    receive do
      :shutdown ->
        Log.info("🛑 Received shutdown message, stopping application...")
        Application.stop(:jamixir)
        System.stop(0)
    after
      :infinity ->
        :ok
    end
  end

  defp input_listener do
    case IO.gets("") do
      "q\n" ->
        send(:shutdown_handler, :shutdown)

      _ ->
        input_listener()
    end
  end

  defp print_help do
    IO.puts("""
    Run a Jamixir node

    Usage: jamixir run [OPTIONS]

    Options:
          --keys <KEYS>              Keys file to load
          --genesis <GENESIS>        Genesis file to use
          --port <PORT>              Port to listen on
      -h, --help                     Print help

    Examples:
      jamixir run --port 10001 --keys ./test/keys/0.json
      MIX_ENV=test jamixir run --port 10002 --keys ./test/keys/1.json
    """)
  end
end
