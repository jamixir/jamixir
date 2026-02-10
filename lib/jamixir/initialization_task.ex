defmodule Jamixir.InitializationTask do
  alias Block
  alias Jamixir.ChainSpec
  alias Jamixir.Genesis
  alias Network.ConnectionManager
  alias Storage
  alias Util.Logger, as: Log
  import Codec.Encoder

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

    case :persistent_term.get({RingVrf, :initialized}, false) do
      true ->
        Log.info("✅ RingVrf context already initialized")

      false ->
        # Initialize if not already done (shouldn't happen in normal flow)
        RingVrf.init_ring_context()
        Log.info("✅ RingVrf context initialized")
    end

    jam_state = init_jam_state()
    Log.info("✅ JAM state initialized")

    Task.start(fn ->
      Log.debug("🔗 Connecting to validators...")
      :ok = ConnectionManager.connect_to_validators(jam_state.curr_validators)
      Log.debug("✅ Validator connections initiated")
    end)

    Log.info("🎉 Initialization task complete")
    :ok
  end

  defp init_jam_state do
    # Check for chainspec first, then fall back to genesis
    chainspec_file = Application.get_env(:jamixir, :chainspec_file)
    genesis_file = Application.get_env(:jamixir, :genesis_file)

    cond do
      chainspec_file ->
        Log.info("🔗 Loading from JIP-4 chain specification: #{chainspec_file}")
        load_from_chainspec(chainspec_file)

      genesis_file && Genesis.chainspec_file?(genesis_file) ->
        Log.info("🔗 Detected JIP-4 chain specification format: #{genesis_file}")
        load_from_chainspec(genesis_file)

      genesis_file ->
        Log.debug("✨ Initializing JAM state from genesis file: #{genesis_file}")
        load_from_genesis(genesis_file)

      true ->
        default_file = Genesis.default_file()
        Log.debug("✨ Initializing JAM state from default genesis file: #{default_file}")
        load_from_genesis(default_file)
    end
  end

  defp load_from_genesis(genesis_file) do
    {:ok, jam_state} = Codec.State.from_genesis(genesis_file)
    storage_and_return_genesis_state(Genesis.genesis_block_header(), jam_state)
  end

  defp load_from_chainspec(chainspec_file) do
    case ChainSpec.from_file(chainspec_file) do
      {:ok, chainspec} ->
        Log.info("📋 Chain ID: #{chainspec.id}")

        # Load and store the genesis header
        {:ok, genesis_header} = ChainSpec.get_header(chainspec)
        Log.debug("📦 Genesis header loaded from chain spec")

        # Load the genesis state
        {:ok, jam_state} = ChainSpec.get_state(chainspec)
        Log.debug("📊 Genesis state loaded with #{map_size(chainspec.genesis_state)} entries")

        # Store the chainspec for later use (e.g., bootnodes)
        Application.put_env(:jamixir, :loaded_chainspec, chainspec)

        storage_and_return_genesis_state(genesis_header, jam_state)

      {:error, reason} ->
        Log.error("❌ Failed to load chain spec: #{inspect(reason)}")
        raise "Failed to load chain specification: #{inspect(reason)}"
    end
  end

  defp storage_and_return_genesis_state(genesis_header, jam_state) do
    genesis_header_hash = h(e(genesis_header))
    genesis_block = %Block{header: genesis_header}

    # Store genesis block so it's in the database
    Storage.put(genesis_block)

    # Store genesis state
    Storage.put(genesis_header, jam_state)

    # Mark genesis block as applied and set as last applied hash
    Storage.mark_applied(genesis_header_hash)

    jam_state
  end
end
