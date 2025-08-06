defmodule Jamixir.Commands.Run do
  @moduledoc """
  Run a Jamixir node
  """
  alias Util.Logger, as: Log

  @switches [
    keys: :string,
    genesis: :string,
    port: :integer,
    socket_path: :string,
    help: :boolean,
    log: :string
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
    if log_level = opts[:log] || "info" do
      Log.info("Setting log level to #{log_level}")
      Logger.configure(level: :"#{log_level}")
    end

    Log.info("🟣 Pump up the JAM, pump it up...")
    Log.debug("System loaded with config: #{inspect(Jamixir.config())}")

    # Only load keys and generate TLS certificates if not in fuzzer mode
    unless Application.get_env(:jamixir, :fuzzer_mode, false) do
      case KeyManager.load_keys(opts[:keys]) do
        {:ok, _} -> :ok
        {:error, e} -> raise e
      end

      if genesis_file = opts[:genesis],
        do: Application.put_env(:jamixir, :genesis_file, genesis_file)

      if port = opts[:port], do: Application.put_env(:jamixir, :port, port)

      generate_tls_certificates()
    end

    # Set socket path for fuzzer mode
    if socket_path = opts[:socket_path],
      do: Application.put_env(:jamixir, :fuzzer_socket_path, socket_path)

    if Application.get_env(:jamixir, :fuzzer_mode, false) do
      Log.info("🎭 Starting as fuzzer")
    else
      Log.info("🎭 Starting as validator")
    end

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

  defp generate_tls_certificates do
    case KeyManager.get_our_ed25519_keypair() do
      {private_key, public_key} ->
        Log.debug(
          "🔐 Generating TLS identity bundle using ed25519 key: #{Util.Hex.encode16(public_key)}"
        )

        case Network.CertUtils.create_pkcs12_bundle(private_key) do
          {:ok, pkcs12_bundle} ->
            Log.info("✅ TLS identity bundle generated successfully")
            Log.debug("📜 Certificate DNS name: #{Network.CertUtils.alt_name(public_key)}")

            Application.put_env(:jamixir, :tls_identity, pkcs12_bundle)
            {:ok, pkcs12_bundle}

          {:error, error} ->
            Log.error("❌ Failed to generate TLS identity bundle: #{inspect(error)}")
            {:error, error}
        end

      nil ->
        Log.error("❌ No ed25519 keys loaded, cannot generate TLS identity bundle")
        System.halt(1)
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
          --socket-path <PATH>       Unix domain socket path for fuzzer mode
          --log <LEVEL>              Log level (none | info | warning | error | debug) default: info
      -h, --help                     Print help

    Examples:
      jamixir run --port 10001 --keys ./test/keys/0.json
      MIX_ENV=test jamixir run --port 10002 --keys ./test/keys/1.json
    """)
  end
end
