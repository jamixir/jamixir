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

    KeyManager.load_keys(opts[:keys])

    if genesis_file = opts[:genesis],
      do: Application.put_env(:jamixir, :genesis_file, genesis_file)

    if port = opts[:port], do: Application.put_env(:jamixir, :port, port)

    # Generate TLS certificates before starting the application
    generate_tls_certificates()

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

  defp generate_tls_certificates do
    case KeyManager.get_our_ed25519_keypair() do
      {private_key, public_key} ->
        Log.debug("🔐 Generating TLS certificate using ed25519 key: #{Util.Hex.encode16(public_key)}")

        case Network.CertUtils.generate_self_signed_certificate(private_key) do
          {:ok, pkcs12_bundle} ->
            Log.info("✅ TLS certificate generated successfully")
            Log.debug("📜 Certificate DNS name: #{Network.CertUtils.alt_name(public_key)}")

            # Store PKCS12 binary in application env for use by listener and connections
            Application.put_env(:jamixir, :tls_identity, pkcs12_bundle)
            {:ok, pkcs12_bundle}

          {:error, error} ->
            Log.error("❌ Failed to generate TLS certificate: #{inspect(error)}")
            {:error, error}
        end

      nil ->
        Log.error("❌ No ed25519 keys loaded, cannot generate TLS certificate")
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
      -h, --help                     Print help

    Examples:
      jamixir run --port 10001 --keys ./test/keys/0.json
      MIX_ENV=test jamixir run --port 10002 --keys ./test/keys/1.json
    """)
  end
end
