{:ok, _} = Application.ensure_all_started(:ex_machina, :quicer)

ExUnit.start()
ExUnit.configure(exclude: [:full_vectors, :check_vectors_count])
# Storage.start_link([persist: false])

Mox.defmock(ValidatorStatisticsMock, for: System.State.ValidatorStatistics)
Mox.defmock(HeaderSealMock, for: System.HeaderSeal)
Mox.defmock(MockAccumulation, for: System.State.Accumulation)
