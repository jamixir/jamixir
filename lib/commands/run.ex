defmodule Jamixir.Commands.Run do
  @moduledoc """
  Run a Jamixir node
  """
  alias Util.Logger, as: Log

  @switches [
    keys: :string,
    genesis: :string,
    chainspec: :string,
    port: :integer,
    socket_path: :string,
    help: :boolean,
    log: :string,
    rpc: :boolean,
    rpc_port: :integer,
    telemetry: :string,
    telemetry_port: :integer
  ]

  @aliases [
    l: :log,
    p: :port,
    k: :keys,
    h: :help,
    c: :chainspec
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
    # Ensure we use production children
    Application.put_env(:jamixir, :start_full_app, true)

    if log_level = opts[:log] || "info" do
      Log.info("Setting log level to #{log_level}")

      Logger.configure(level: :"#{log_level}")

      Logger.configure_backend(:console,
        format: "$date $time [$level] $message $metadata\n",
        metadata: [:request_id]
      )
    end

    log_system_info()
    Log.info("🟣 Pump up the JAM, pump it up...")
    Log.debug("System loaded with config: #{inspect(Jamixir.config())}")

    # Only load keys and generate TLS certificates if not in fuzzer mode
    unless Application.get_env(:jamixir, :fuzzer_mode, false) do
      case KeyManager.load_keys(opts[:keys]) do
        {:ok, _} -> :ok
        {:error, e} -> raise e
      end
    end

    node_id = Jamixir.NodeIdentity.initialize!()
    Log.info("🆔 Node ID: #{node_id}")

    # Configure Mnesia directory BEFORE any application supervision starts
    configure_mnesia_directory!()

    Log.info("""
     Storage Configuration:
     Base dir: #{Jamixir.NodeIdentity.base_dir()}/#{node_id}
    """)

    unless Application.get_env(:jamixir, :fuzzer_mode, false) do
      if genesis_file = opts[:genesis],
        do: Application.put_env(:jamixir, :genesis_file, genesis_file)

      if chainspec_file = opts[:chainspec],
        do: Application.put_env(:jamixir, :chainspec_file, chainspec_file)

      if port = opts[:port], do: Application.put_env(:jamixir, :port, port)

      # Configure RPC based on flags
      configure_rpc(opts)

      # Configure telemetry based on flags
      configure_telemetry(opts)

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

    RingVrf.init_ring_context()

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

  defp configure_rpc(opts) do
    cond do
      rpc_port = opts[:rpc_port] ->
        Application.put_env(:jamixir, :rpc_enabled, true)
        Application.put_env(:jamixir, :rpc_port, rpc_port)

      opts[:rpc] ->
        Application.put_env(:jamixir, :rpc_enabled, true)

      # Otherwise, disable RPC
      true ->
        Log.info("🔌 RPC disabled")
        Application.put_env(:jamixir, :rpc_enabled, false)
    end
  end

  defp configure_mnesia_directory! do
    node_dir = Jamixir.NodeIdentity.node_dir()
    mnesia_dir = Path.join(node_dir, "mnesia")
    File.mkdir_p!(mnesia_dir)
    Application.put_env(:mnesia, :dir, mnesia_dir)
  end

  defp configure_telemetry(opts) do
    cond do
      # Format: --telemetry HOST:PORT
      telemetry_arg = opts[:telemetry] ->
        case String.split(telemetry_arg, ":") do
          [host, port_str] ->
            case Integer.parse(port_str) do
              {port, ""} ->
                Log.info("📊 Telemetry enabled: #{host}:#{port}")
                Application.put_env(:jamixir, :telemetry_enabled, true)
                Application.put_env(:jamixir, :telemetry_host, host)
                Application.put_env(:jamixir, :telemetry_port, port)

              _ ->
                Log.error("❌ Invalid telemetry port: #{port_str}")
                System.halt(1)
            end

          _ ->
            Log.error("❌ Invalid telemetry format. Use: --telemetry HOST:PORT")
            System.halt(1)
        end

      # Separate host and port arguments (legacy support)
      opts[:telemetry_port] ->
        Log.info("📊 Telemetry enabled on port #{opts[:telemetry_port]}")
        Application.put_env(:jamixir, :telemetry_enabled, true)
        Application.put_env(:jamixir, :telemetry_host, "localhost")
        Application.put_env(:jamixir, :telemetry_port, opts[:telemetry_port])

      # Otherwise, disable telemetry
      true ->
        Application.put_env(:jamixir, :telemetry_enabled, false)
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

  defp log_system_info do
    # Basic info (you already have)
    schedulers = :erlang.system_info(:schedulers)
    schedulers_online = :erlang.system_info(:schedulers_online)
    kernel_poll = :erlang.system_info(:kernel_poll)
    async_threads = :erlang.system_info(:thread_pool_size)

    # Memory info
    memory = :erlang.memory()
    total_memory_mb = memory[:total] / (1024 * 1024)

    # Version info
    {elixir_version, _} = System.version() |> Version.parse!() |> then(&{&1, nil})
    otp_version = :erlang.system_info(:otp_release)

    # Additional performance-critical settings
    process_limit = :erlang.system_info(:process_limit)
    port_limit = :erlang.system_info(:port_limit)
    atom_limit = :erlang.system_info(:atom_limit)

    # Memory allocator info
    allocator_info = get_allocator_summary()

    # CPU/Hardware info
    logical_processors = :erlang.system_info(:logical_processors_available) || "unknown"
    cpu_topology = get_cpu_topology()

    # Process and port counts
    process_count = :erlang.system_info(:process_count)
    port_count = :erlang.system_info(:port_count)

    # ETS info
    ets_limit = :erlang.system_info(:ets_limit)

    # Garbage collection info
    gc_info = get_gc_info()

    Log.info("🔧 System Configuration:")
    Log.info("├─ Schedulers: #{schedulers}")
    Log.info("├─ Schedulers online: #{schedulers_online}")
    Log.info("├─ Logical processors: #{logical_processors}")
    Log.info("├─ CPU topology: #{cpu_topology}")
    Log.info("├─ Kernel poll: #{kernel_poll}")
    Log.info("├─ Async threads: #{async_threads}")
    Log.info("├─ Process limit: #{process_limit} (current: #{process_count})")
    Log.info("├─ Port limit: #{port_limit} (current: #{port_count})")
    Log.info("├─ ETS limit: #{ets_limit}")
    Log.info("├─ Atom limit: #{atom_limit}")
    Log.info("├─ Total memory: #{Float.round(total_memory_mb, 1)} MB")
    Log.info("├─ Memory breakdown: #{format_memory_breakdown(memory)}")
    Log.info("├─ Memory allocators: #{allocator_info}")
    Log.info("├─ GC settings: #{gc_info}")

    Log.info(
      "├─ OS: #{inspect(:erlang.system_info(:os_type))} #{inspect(:erlang.system_info(:os_version))}"
    )

    Log.info("├─ Elixir: #{elixir_version}")
    Log.info("└─ Erlang/OTP: #{otp_version}")
  end

  defp get_allocator_summary do
    try do
      allocators = :erlang.system_info(:alloc_util_allocators)

      # Get key allocator strategies - fix the data access
      strategies =
        for alloc <- allocators do
          info = :erlang.system_info({:allocator, alloc})

          # The info is a list of instances, get the strategy from first instance
          strategy =
            case info do
              [{:instance, _, instance_info} | _] ->
                get_in(instance_info, [:options, :as]) || "default"

              _ ->
                "unknown"
            end

          "#{alloc}:#{strategy}"
        end

      Enum.join(strategies, ", ")
    rescue
      e -> "error: #{inspect(e)}"
    end
  end

  defp get_cpu_topology do
    try do
      case :erlang.system_info(:cpu_topology) do
        :undefined ->
          "undefined"

        topology ->
          # Fix the string concatenation
          topology_str = inspect(topology)

          if String.length(topology_str) > 50 do
            String.slice(topology_str, 0, 50) <> "..."
          else
            topology_str
          end
      end
    rescue
      _ -> "unavailable"
    end
  end

  defp get_gc_info do
    try do
      # Get default process GC settings
      [
        max_heap_size: max_heap_size,
        min_bin_vheap_size: min_bin_vheap_size,
        min_heap_size: min_heap_size,
        fullsweep_after: fullsweep
      ] =
        :erlang.system_info(:garbage_collection)

      "max_heap_size:#{max_heap_size}, min_bin_vheap_size:#{min_bin_vheap_size}, min_heap_size:#{min_heap_size}, fullsweep_after:#{fullsweep}"
    rescue
      _ -> "unavailable"
    end
  end

  defp format_memory_breakdown(memory) do
    # Show key memory categories as percentages
    total = memory[:total]

    breakdown = [
      {"processes", memory[:processes]},
      {"binary", memory[:binary]},
      {"code", memory[:code]},
      {"ets", memory[:ets]}
    ]

    parts =
      for {name, size} <- breakdown do
        pct = Float.round(size / total * 100, 1)
        "#{name}:#{pct}%"
      end

    Enum.join(parts, ", ")
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
           MIX_ENV=<env> jamixir run [OPTIONS]

    Options:
      -k, --keys <KEYS>              Keys file to load
          --genesis <GENESIS>        Genesis file to use (legacy format)
      -c, --chainspec <CHAINSPEC>    JIP-4 chain specification file to use
      -p, --port <PORT>              Network port to listen on
          --socket-path <PATH>       Unix domain socket path for fuzzer mode
      -l, --log <LEVEL>              Log level (none | info | warning | error | debug) default: info
          --rpc                      Enable RPC server on default port (19800)
          --rpc-port <PORT>          Enable RPC server on specified port
          --telemetry <HOST:PORT>    Enable telemetry reporting (e.g. --telemetry localhost:9090)
          --telemetry-port <PORT>    Enable telemetry on localhost with specified port
      -h, --help                     Print help

    Examples:
      jamixir run --keys ./test/keys/0.json
      jamixir run --chainspec ./chainspec.json --keys ./test/keys/0.json
      jamixir run --keys ./test/keys/0.json --rpc
      jamixir run --keys ./test/keys/0.json --rpc-port 20000
      jamixir run --keys ./test/keys/0.json --telemetry localhost:9000
      MIX_ENV=tiny jamixir run --keys ./test/keys/0.json
      MIX_ENV=tiny jamixir run -c ./chainspec.json -k ./test/keys/1.json -p 10002
      MIX_ENV=prod jamixir run --port 10001 --keys ./test/keys/0.json --rpc --telemetry localhost:9000
      MIX_ENV=tiny jamixir run -k ./test/keys/1.json -p 10002 --rpc-port 19801

    Configuration Environments:
      - tiny:      Small network (6 validators, short epochs) - good for testing
      - prod:      Production settings (1023 validators, full parameters)

    Note: --chainspec takes precedence over --genesis if both are specified.
          The system will auto-detect JIP-4 format if using --genesis with a chainspec file.
    """)
  end
end
