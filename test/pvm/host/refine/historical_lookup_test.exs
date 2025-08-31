defmodule PVM.Host.Refine.HistoricalLookupTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Registers, PreMemory}
  alias System.State.ServiceAccount
  import PVM.Constants.HostCallResult
  import PVM.Memory.Constants
  alias Util.Hash

  defp a_0, do: min_allowed_address()

  describe "historical_lookup/6" do
    setup do
      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.set_access(a_0(), page_size() + 100, :write)
        |> PreMemory.finalize()

      context = %Context{}
      some_big_value = 0xFFFF

      test_value = Hash.two()

      test_map = %{
        hash: Hash.default(test_value),
        length: byte_size(test_value),
        value: test_value
      }

      gas = 100

      service_accounts = %{
        1 => %ServiceAccount{
          preimage_storage_p: %{
            test_map.hash => test_value
          },
          storage: HashedKeysMap.new(%{{test_map.hash, test_map.length} => [1]})
        }
      }

      registers = Registers.new(%{
        7 => 1,
        8 => a_0(),
        9 => a_0() + page_size() + 100,
        10 => 0,
        11 => some_big_value
      })

      {:ok,
       memory: memory,
       context: context,
       service_accounts: service_accounts,
       timeslot: 123,
       test_map: test_map,
       gas: gas,
       registers: registers}
    end

    test "{:continue, none()} when service account doesn't exist", %{
      memory: memory,
      context: context,
      service_accounts: service_accounts,
      timeslot: timeslot,
      gas: gas,
      registers: registers
    } do
      # Set w7 to non-existent service account ID
      registers = %{registers | r: put_elem(registers.r, 7, 999)}
      none = none()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: ^context
             } =
               Refine.historical_lookup(
                 gas,
                 registers,
                 memory,
                 context,
                 1,
                 service_accounts,
                 timeslot
               )

      assert registers_[7] == none
    end

    test "{:panic, w7} when memory is not readable", %{
      memory: memory,
      context: context,
      service_accounts: service_accounts,
      timeslot: timeslot,
      gas: gas,
      registers: registers
    } do
      # 1 is the start address in memory
      registers = %{registers | r: put_elem(registers.r, 8, 1)}

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } =
               Refine.historical_lookup(
                 gas,
                 registers,
                 memory,
                 context,
                 1,
                 service_accounts,
                 timeslot
               )
    end

    test "{:panic, w7} when memory is not writable", %{
      memory: memory,
      context: context,
      service_accounts: service_accounts,
      timeslot: timeslot,
      test_map: test_map,
      gas: gas,
      registers: registers
    } do
      memory = Memory.write!(memory, registers[8], test_map.hash)
      memory = Memory.set_access_by_page(memory, 17, 1, :read)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } =
               Refine.historical_lookup(
                 gas,
                 registers,
                 memory,
                 context,
                 1,
                 service_accounts,
                 timeslot
               )
    end

    test "successful lookup with valid parameters", %{
      memory: memory,
      context: context,
      service_accounts: service_accounts,
      timeslot: timeslot,
      test_map: test_map,
      gas: gas,
      registers: registers
    } do
      memory = Memory.write!(memory, registers[8], test_map.hash)
      %{length: l, value: v} = test_map

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: context_
             } =
               Refine.historical_lookup(
                 gas,
                 registers,
                 memory,
                 context,
                 99,
                 service_accounts,
                 timeslot
               )

      assert registers_[7] == l

      # Verify the value was written to memory
      {:ok, ^v} = Memory.read(memory_, registers[9], l)

      assert context_ == context
    end

    test "handles max_64_bit w7 value with valid index", %{
      memory: memory,
      context: context,
      service_accounts: service_accounts,
      timeslot: timeslot,
      test_map: test_map,
      gas: gas,
      registers: registers
    } do
      %{length: l, value: v} = test_map
      memory = Memory.write!(memory, registers[8], test_map.hash)

      # Setup registers with max 64-bit value (0xFFFF_FFFF_FFFF_FFFF)
      registers = %{registers | r: put_elem(registers.r, 7, 0xFFFF_FFFF_FFFF_FFFF)}

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: context_
             } =
               Refine.historical_lookup(
                 gas,
                 registers,
                 memory,
                 context,
                 1,
                 service_accounts,
                 timeslot
               )

      assert registers_[7] == l

      # Verify the value was written to memory
      {:ok, ^v} = Memory.read(memory_, registers[9], l)

      assert context_ == context
    end
  end
end
