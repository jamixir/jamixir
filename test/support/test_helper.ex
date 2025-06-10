defmodule TestHelper do
  alias System.State.Validator
  alias Util.Hash
  alias Util.Time, as: Time
  import Mox

  def past_timeslot do
    div(Time.current_time() - 10, Constants.slot_period())
  end

  def future_timeslot do
    div(Time.current_time() + 10, Constants.slot_period())
  end

  def nullified?(%Validator{} = validator), do: Validator.key(validator) == <<0::336*8>>

  def mock_header_seal do
    stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
      {:ok, %{vrf_signature_output: Hash.zero()}}
    end)
  end

  def mock_statistics do
    ValidatorStatisticsMock
    |> stub(:do_transition, fn _, _, _, _, _, _, _ -> {:ok, "mockvalue"} end)
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
