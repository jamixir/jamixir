ExUnit.start()

defmodule TestHelper do
  alias Util.Time, as: Time
  alias System.State.Validator

  def past_timeslot do
    div(Time.current_time() - 10, Time.block_duration())
  end

  def future_timeslot do
    div(Time.current_time() + 10, Time.block_duration())
  end

  def is_nullified(%Validator{} = validator) do
    validator.bandersnatch == <<0::256>> and
      validator.ed25519 == <<0::256>> and
      validator.bls == <<0::1152>> and
      validator.metadata == <<0::1024>>
  end

  def random_validator do
    %Validator{
      bandersnatch: :crypto.strong_rand_bytes(32),
      ed25519: :crypto.strong_rand_bytes(32),
      bls: :crypto.strong_rand_bytes(144),
      metadata: :crypto.strong_rand_bytes(128)
    }
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
