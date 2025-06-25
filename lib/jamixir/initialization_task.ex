defmodule Jamixir.InitializationTask do
  alias Network.ConnectionManager
  alias Util.Logger, as: Log

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

    :persistent_term.put(:jam_state, jam_state)

    resolve_our_address(jam_state.curr_validators)
    Log.info("✅ Validator address resolved")

    Task.start(fn ->
      Log.debug("🔗 Connecting to validators...")
      :ok = ConnectionManager.connect_to_validators(jam_state.curr_validators)
      Log.debug("✅ Validator connections initiated")
    end)

    Log.info("🎉 Initialization task complete")
    :ok
  end

  defp init_jam_state do
    genesis_file = Application.get_env(:jamixir, :genesis_file, "genesis/genesis.json")
    Log.debug("✨ Initializing JAM state from genesis file: #{genesis_file}")
    {:ok, jam_state} = Codec.State.from_genesis(genesis_file)
    Storage.put(jam_state)
    jam_state
  end

  # Resolve our address by finding ourselves in the validators list using our ed25519 key
  defp resolve_our_address(validators) do
    case KeyManager.get_our_ed25519_key() do
      nil ->
        Log.warning("⚠️  No ed25519 key found - cannot determine address in production mode")

      our_key ->
        case find_our_validator(validators, our_key) do
          nil ->
            Log.warning("⚠️  Could not find our validator in the validators list")

          our_validator ->
            import System.State.Validator, only: [address: 1]
            address = address(our_validator)
            Application.put_env(:jamixir, :our_validator_address, address)
            Log.debug("📍 Production mode - resolved our address: #{address}")
        end
    end
  end

  # Find our validator in the validators list using our ed25519 key
  defp find_our_validator(validators, our_key) do
    Enum.find(validators, fn validator ->
      validator.ed25519 == our_key
    end)
  end
end
