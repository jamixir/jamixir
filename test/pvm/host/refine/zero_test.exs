defmodule PVM.Host.Refine.ZeroTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Integrated, Registers, PreMemory}
  import PVM.Constants.HostCallResult
  import PVM.Memory.Constants

  describe "zero/4" do
    setup do
      # Create machine memory with test data
      test_data = String.duplicate("A", 256)

      machine_memory =
        PreMemory.init_nil_memory()
        |> PreMemory.set_access(min_allowed_address(), page_size() + 2, :write)
        |> PreMemory.write(min_allowed_address(), test_data)
        |> PreMemory.finalize()

      machine = %Integrated{
        memory: machine_memory,
        program: "program"
      }

      context = %Context{m: %{1 => machine}}
      gas = 100

      # r7: machine ID, r8: start page, r9: page count
      registers = %Registers{
        r7: 1,
        r8: 16,
        r9: 2
      }

      {:ok,
       context: context, machine: machine, gas: gas, registers: registers, test_data: test_data}
    end

    test "returns WHO when machine doesn't exist", %{
      gas: gas,
      registers: registers,
      context: context
    } do
      memory = %Memory{}
      who = who()
      registers = %{registers | r7: 99}

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^who},
               memory: ^memory,
               context: ^context
             } = Refine.zero(gas, registers, memory, context)
    end

    test "returns HUH when page number is too small", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      memory = %Memory{}
      # Set start page below minimum (16)
      registers = %{registers | r8: 15}
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^huh},
               memory: ^memory,
               context: ^context
             } = Refine.zero(gas, registers, memory, context)
    end

    test "returns HUH when page range is too large", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      memory = %Memory{}
      # Set page count to exceed 2^32/page_size
      registers = %{registers | r8: 0x1_FFFE, r9: 4}
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^huh},
               memory: ^memory,
               context: ^context
             } = Refine.zero(gas, registers, memory, context)
    end

    test "successful zero with valid parameters", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      memory = %Memory{}
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^ok},
               memory: ^memory,
               context: context_
             } = Refine.zero(gas, registers, memory, context)

      # Get updated machine
      machine = Map.get(context_.m, 1)
      page_size = machine.memory.page_size

      # Calculate range
      start_offset = registers.r8 * page_size
      length = registers.r9 * page_size

      # Verify pages are zeroed
      {:ok, zeroed_data} = Memory.read(machine.memory, start_offset, length)
      assert zeroed_data == <<0::size(length * 8)>>

      # Verify pages are writable
      assert Memory.check_range_access?(machine.memory, start_offset, length, :write)
    end
  end
end
