defmodule PVM.Host.Refine.HistoricalLookupTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Registers, Host.Refine.Result}
  alias System.State.ServiceAccount
  import PVM.Constants.HostCallResult
  alias Util.Hash

  describe "historical_lookup/6" do
    setup do
      # Setup basic test data
      memory = %Memory{}
      context = %Context{}

      test_value = Hash.two()
      test_hash = Hash.default(test_value)
      gas = 100

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
       service_accounts: service_accounts,
       timeslot: 123,
       test_hash: test_hash,
       test_value: test_value,
       gas: gas}
    end

    test "returns WHO when service account doesn't exist", %{
      memory: memory,
      context: context,
      service_accounts: service_accounts,
      timeslot: timeslot,
      gas: gas
    } do
      # Set w7 to non-existent service account ID
      registers = %Registers{r7: 999}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.historical_lookup(gas, registers, memory, context, 1, service_accounts, timeslot)

      assert registers_ == Registers.set(registers, 7, none())
      assert memory_ == memory
      assert context_ == context
    end

    test "returns OOB when memory is not readable", %{
      memory: memory,
      context: context,
      service_accounts: service_accounts,
      timeslot: timeslot,
      gas: gas
    } do
      # 1 is the start address in memory
      registers = %Registers{r8: 1}

      # Memory is not readable
      memory = Memory.set_access(memory, 1, 1, nil)

      # h will be :error => expectig oob

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.historical_lookup(gas, registers, memory, context, 1, service_accounts, timeslot)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == memory
      assert context_ == context
    end

    test "return oob when memory is not writable", %{
      memory: memory,
      context: context,
      service_accounts: service_accounts,
      timeslot: timeslot,
      gas: gas
    } do
      registers = %Registers{r8: 1, r9: 64, r10: 32}

      # Memory is not writable
      # bo...+bz is not all writable
      memory = Memory.set_access(memory, 100, 1, :read)

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.historical_lookup(gas, registers, memory, context, 1, service_accounts, timeslot)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == memory
      assert context_ == context
    end

    test "successful lookup with valid parameters", %{
      memory: memory,
      context: context,
      service_accounts: service_accounts,
      timeslot: timeslot,
      test_value: test_value,
      gas: gas
    } do
      # Write hash to memory
      {:ok, memory} = Memory.write(memory, 0, test_value)

      # Setup registers
      registers = %Registers{r7: 1, r8: 0, r9: 100, r10: byte_size(test_value)}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.historical_lookup(gas, registers, memory, context, 1, service_accounts, timeslot)

      assert registers_ == Registers.set(registers, 7, byte_size(test_value))

      # Verify the value was written to memory
      {:ok, ^test_value} = Memory.read(memory_, 100, byte_size(test_value))

      assert context_ == context
    end
  end
end
