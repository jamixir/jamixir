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
    log: :string,
    size: :string
  ]

  @aliases [
    l: :log,
    p: :port,
    k: :keys,
    h: :help,
    s: :size
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
    set_mix_env_for_size(opts[:size])

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

      if genesis_file = opts[:genesis],
        do: Application.put_env(:jamixir, :genesis_file, genesis_file)

      if port = opts[:port], do: Application.put_env(:jamixir, :port, port)

      # Find an available RPC port to avoid conflicts
      rpc_port = find_available_port(19800)
      Application.put_env(:jamixir, :rpc_port, rpc_port)

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

  defp set_mix_env_for_size(size) do
    case size do
      "tiny" ->
        Log.info("📏 Setting environment to tiny ")
        System.put_env("MIX_ENV", "tiny")
        Application.put_env(:jamixir, :start_full_app, true)

      "prod" ->
        Log.info("📏 Setting environment to prod")
        System.put_env("MIX_ENV", "prod")
        Application.put_env(:jamixir, :start_full_app, true)

      _ ->
        Log.info("📏 Using (default) tiny environment")
        System.put_env("MIX_ENV", "tiny")
        Application.put_env(:jamixir, :start_full_app, true)
    end
  end



  defp find_available_port(start_port) do
    case :gen_tcp.listen(start_port, []) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        start_port

      {:error, :eaddrinuse} ->
        find_available_port(start_port + 1)

      {:error, reason} ->
        Log.warning("⚠️  Could not test port #{start_port}: #{inspect(reason)}")
        find_available_port(start_port + 1)
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

    Options:
      -k, --keys <KEYS>              Keys file to load
          --genesis <GENESIS>        Genesis file to use
      -p, --port <PORT>              Network port to listen on
          --socket-path <PATH>       Unix domain socket path for fuzzer mode
      -l, --log <LEVEL>              Log level (none | info | warning | error | debug) default: info
      -s, --size <SIZE>              Configuration size (tiny | dev | prod | test | full_test)
      -h, --help                     Print help

    Examples:
      jamixir run --keys ./test/keys/0.json
      jamixir run --size tiny --keys ./test/keys/0.json
      jamixir run --port 10001 --keys ./test/keys/0.json
      jamixir run -s tiny -k ./test/keys/1.json -p 10002


    """)
  end
end
