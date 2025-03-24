defmodule PVM.Host.Refine.VoidTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Integrated, Registers, PreMemory}
  import PVM.Constants.HostCallResult
  import PVM.Memory.Constants

  describe "void/4" do
    setup do
      # Create machine memory with test data and read access
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
      registers: registers
    } do
      context = %Context{}
      memory = %Memory{}
      who = who()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^who},
               memory: ^memory,
               context: ^context
             } = Refine.void(gas, registers, memory, context)
    end

    test "returns HUH when page number is too small", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      memory = %Memory{}
      registers = %{registers | r8: 15}
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^huh},
               memory: ^memory,
               context: ^context
             } = Refine.void(gas, registers, memory, context)
    end

    test "returns HUH when page range is too large", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      memory = %Memory{}
      registers = %{registers | r8: 0x1_FFFE, r9: 4}
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^huh},
               memory: ^memory,
               context: ^context
             } = Refine.void(gas, registers, memory, context)
    end

    test "successful void with valid parameters", %{
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
             } = Refine.void(gas, registers, memory, context)

      # Get updated machine
      machine = Map.get(context_.m, 1)
      page_size = machine.memory.page_size
      [p1, p2] = for p <- Registers.get(registers, [8, 9]), do: p * page_size

      refute Memory.check_range_access?(machine.memory, p1, p2, :read)
    end
  end
end
