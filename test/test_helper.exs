{:ok, _} = Application.ensure_all_started(:ex_machina)

ExUnit.start()
ExUnit.configure(exclude: [:test_vectors, :test_vectors_local])

Mox.defmock(ValidatorStatisticsMock, for: System.State.ValidatorStatistics)
Mox.defmock(HeaderSealMock, for: System.HeaderSeal)

defmodule TestHelper do
  alias Util.Time, as: Time
  alias System.State.Validator

  def past_timeslot do
    div(Time.current_time() - 10, Time.block_duration())
  end

  def future_timeslot do
    div(Time.current_time() + 10, Time.block_duration())
  end

  def nullified?(%Validator{} = validator) do
    validator.bandersnatch == <<0::256>> and
      validator.ed25519 == <<0::256>> and
      validator.bls == <<0::1152>> and
      validator.metadata == <<0::1024>>
  end

  def create_validator(index) do
    %Validator{
      bandersnatch: <<index::256>>,
      ed25519: <<index::256>>,
      bls: <<index::1152>>,
      metadata: <<index::1024>>
    }
  end
end
