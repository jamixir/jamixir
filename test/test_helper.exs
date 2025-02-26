{:ok, _} = Application.ensure_all_started(:ex_machina, :quicer)

ExUnit.configure(timeout: 180_000)
ExUnit.start()
ExUnit.configure(exclude: [:full_vectors, :check_vectors_count, :generate_blocks])
# Storage.start_link([persist: false])

Mox.defmock(ValidatorStatisticsMock, for: System.State.ValidatorStatistics)
Mox.defmock(HeaderSealMock, for: System.HeaderSeal)
Mox.defmock(MockAccumulation, for: System.State.Accumulation)
Mox.defmock(MockPVM, for: PVM)
Mox.defmock(Jamixir.NodeAPI.Mock, for: Jamixir.NodeAPI)
Application.put_env(:jamixir, NodeAPI, Jamixir.NodeAPI.Mock)
