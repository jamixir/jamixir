defmodule Jamixir.InitializationTask do
  alias Network.{ConnectionManager, CertUtils}
  alias Util.Logger, as: Log
  alias Util.Hex
  alias Jamixir.Genesis

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {Task.Supervisor, :start_child, [Jamixir.TaskSupervisor, __MODULE__, :run, []]},
      restart: :temporary,
      type: :worker
    }
  end

  def run do
    Log.info("🚀 Starting initialization task...")

    RingVrf.init_ring_context()
    Log.info("✅ RingVrf context initialized")

    jam_state = init_jam_state()
    Log.info("✅ JAM state initialized")

    generate_tls_certificates()
    Log.info("✅ TLS certificates generated")

    Task.start(fn ->
      Log.debug("🔗 Connecting to validators...")
      :ok = ConnectionManager.connect_to_validators(jam_state.curr_validators)
      Log.debug("✅ Validator connections initiated")
    end)

    Log.info("🎉 Initialization task complete")
    :ok
  end

  defp init_jam_state do
    genesis_file = Application.get_env(:jamixir, :genesis_file, Genesis.default_file())
    Log.debug("✨ Initializing JAM state from genesis file: #{genesis_file}")
    {:ok, jam_state} = Codec.State.from_genesis(genesis_file)
    Storage.put(Genesis.genesis_block_header(), jam_state)
    jam_state
  end

  defp generate_tls_certificates do
    case KeyManager.get_our_ed25519_keypair() do
      {private_key, public_key} ->
        Log.debug("🔐 Generating TLS certificate using ed25519 key: #{Hex.encode16(public_key)}")

        case CertUtils.generate_self_signed_certificate(private_key) do
          {:ok, cert} ->
            Log.info("✅ TLS certificate generated successfully")
            Log.debug("📜 Certificate DNS name: #{CertUtils.alt_name(public_key)}")
            {:ok, cert}

          {:error, error} ->
            Log.error("❌ Failed to generate TLS certificate: #{inspect(error)}")
            {:error, error}
        end

      nil ->
        Log.warning("⚠️ No ed25519 keys loaded, skipping certificate generation")
        {:error, :no_keys_loaded}
    end
  end
end
