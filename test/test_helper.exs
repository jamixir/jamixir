{:ok, _} = Application.ensure_all_started(:ex_machina)

ExUnit.start()
ExUnit.configure(exclude: [:full_vectors])
Storage.start_link()

Mox.defmock(ValidatorStatisticsMock, for: System.State.ValidatorStatistics)
Mox.defmock(HeaderSealMock, for: System.HeaderSeal)
Mox.defmock(MockAccumulation, for: System.State.Accumulation)

defmodule TestHelper do
  alias System.State.Validator
  alias Util.Hash
  alias Util.Time, as: Time

  def past_timeslot do
    div(Time.current_time() - 10, Constants.slot_period())
  end

  def future_timeslot do
    div(Time.current_time() + 10, Constants.slot_period())
  end

  def nullified?(%Validator{} = validator) do
    validator.bandersnatch == Hash.zero() and
      validator.ed25519 == Hash.zero() and
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

  defmacro setup_validators(validator_count) do
    quote do
      defmodule ConstantsMock do
        def validator_count, do: unquote(validator_count)
      end

      setup do
        Application.put_env(:jamixir, Constants, ConstantsMock)

        on_exit(fn ->
          Application.delete_env(:jamixir, Constants)
        end)
      end
    end
  end

  defmacro setup_constants(do: block) do
    quote do
      defmodule ConstantsMock do
        unquote(block)
      end

      setup do
        Application.put_env(:jamixir, Constants, ConstantsMock)

        on_exit(fn ->
          Application.delete_env(:jamixir, Constants)
        end)
      end
    end
  end
end
