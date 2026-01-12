{:ok, _} = Application.ensure_all_started(:ex_machina, :quicer)

ExUnit.configure(timeout: 180_000)
ExUnit.start()
ExUnit.configure(exclude: [:full_vectors, :check_vectors_count, :generate_blocks, :slow])
# Initialize ring context once globally
RingVrf.init_ring_context(20)

Mox.defmock(ValidatorStatisticsMock, for: System.State.ValidatorStatistics)
Mox.defmock(HeaderSealMock, for: System.HeaderSeal)
Mox.defmock(MockAccumulation, for: System.State.Accumulation)
Mox.defmock(MockPVM, for: PVM)
Mox.defmock(Jamixir.NodeAPI.Mock, for: Jamixir.NodeAPI)
Mox.defmock(ErasureCodingMock, for: ErasureCoding)
Mox.defmock(ServerCallsMock, for: Network.ServerCallsBehaviour)
Mox.defmock(DAMock, for: System.DataAvailability)
Mox.defmock(NodeStateServerMock, for: Jamixir.NodeStateServerBehaviour)
Mox.defmock(ClientMock, for: Network.ClientAPI)
Mox.defmock(ConnectionManagerMock, for: Network.ConnectionManager)

# Optional: remove or move to test setup unless needed globally
Application.put_env(:jamixir, NodeAPI, Jamixir.NodeAPI.Mock)
Application.put_env(:jamixir, :data_availability, DAMock)

# Set sandbox mode
Ecto.Adapters.SQL.Sandbox.mode(Jamixir.Repo, :manual)

# Profiling
if after_suite_fn = Test.Profiling.setup() do
  ExUnit.after_suite(after_suite_fn)
end
