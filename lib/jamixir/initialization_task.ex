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
end
