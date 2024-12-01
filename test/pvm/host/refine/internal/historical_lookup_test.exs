defmodule PVM.Host.Refine.Internal.HistoricalLookupTest do
  use ExUnit.Case
  alias PVM.Host.Refine.Internal
  alias PVM.{Memory, RefineContext}
  alias System.State.ServiceAccount
  import PVM.Constants.HostCallResult
  alias Util.Hash

  describe "historical_lookup_pure/6" do
    setup do
      # Setup basic test data
      memory = %Memory{}
      context = %RefineContext{}
      # Initialize 13 registers with zeros
      registers = List.duplicate(0, 13) |> List.replace_at(7, 1)
      test_value = Hash.two()
      test_hash = Hash.default(test_value)

      service_accounts = %{
        1 => %ServiceAccount{
          # Present storage
          preimage_storage_p: %{
            # Map of hash => value pairs for testing
            test_hash => test_value
          },
          # Legacy storage (empty for this test)
          preimage_storage_l: %{{test_hash, byte_size(test_value)} => [1]}
        }
      }

      {:ok,
       memory: memory,
       context: context,
       registers: registers,
       service_accounts: service_accounts,
       timeslot: 123,
       test_hash: test_hash,
       test_value: test_value}
    end

    test "returns WHO when service account doesn't exist", %{
      memory: memory,
      context: context,
      registers: registers,
      service_accounts: service_accounts,
      timeslot: timeslot
    } do
      # Set w7 to non-existent service account ID
      registers = List.replace_at(registers, 7, 999)

      {new_registers, new_memory, new_context} =
        Internal.historical_lookup_pure(registers, memory, context, 1, service_accounts, timeslot)

      assert new_registers == List.replace_at(registers, 7, none())
      assert new_memory == memory
      assert new_context == context
    end

    test "returns OOB when memory is not readable", %{
      memory: memory,
      context: context,
      registers: registers,
      service_accounts: service_accounts,
      timeslot: timeslot
    } do
      # 1 is the start address in memory
      registers =
        List.replace_at(registers, 8, 1)

      # Memory is not readable
      memory = Memory.set_access(memory, 1, 1, nil)

      # h will be :error => expectig oob

      {new_registers, new_memory, new_context} =
        Internal.historical_lookup_pure(registers, memory, context, 1, service_accounts, timeslot)

      assert Enum.at(new_registers, 7) == oob()
      assert new_memory == memory
      assert new_context == context
    end

    test "return oob when memory is not writable", %{
      memory: memory,
      context: context,
      registers: registers,
      service_accounts: service_accounts,
      timeslot: timeslot
    } do
      registers =
        List.replace_at(registers, 8, 1)
        |> List.replace_at(9, 64)
        |> List.replace_at(10, 32)

      # Memory is not writable
      # bo...+bz is not all writable
      memory = Memory.set_access(memory, 100, 1, :read)

      {new_registers, new_memory, new_context} =
        Internal.historical_lookup_pure(registers, memory, context, 1, service_accounts, timeslot)

      assert Enum.at(new_registers, 7) == oob()
      assert new_memory == memory
      assert new_context == context
    end

    test "successful lookup with valid parameters", %{
      memory: memory,
      context: context,
      registers: registers,
      service_accounts: service_accounts,
      timeslot: timeslot,
      test_hash: test_hash,
      test_value: test_value
    } do
      # Write hash to memory
      {:ok, memory} = Memory.write(memory, 0, test_value)

      # Setup registers
      registers =
        registers
        # hash offset
        |> List.replace_at(8, 0)
        # buffer offset
        |> List.replace_at(9, 100)
        # buffer size
        |> List.replace_at(10, byte_size(test_value))

      {new_registers, new_memory, new_context} =
        Internal.historical_lookup_pure(registers, memory, context, 1, service_accounts, timeslot)

      assert Enum.at(new_registers, 7) == ok()

      # Verify the value was written to memory
      {:ok, written_value} = Memory.read(new_memory, 100, byte_size(test_value))
      assert written_value == test_value

      assert new_context == context
    end
  end
end
