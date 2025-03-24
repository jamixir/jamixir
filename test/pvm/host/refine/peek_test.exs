defmodule PVM.Host.Refine.PeekTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Integrated, Registers, PreMemory}
  import PVM.Constants.HostCallResult
  import PVM.Memory.Constants

  defp a_0, do: min_allowed_address()

  describe "peek/4" do
    setup do
      memory = PreMemory.init_nil_memory()
        |> PreMemory.set_access(a_0(), 1, :write)

        |> PreMemory.finalize()

      context = %Context{}
      gas = 100


      test_data = String.duplicate("A", 32)
      source_memory = PreMemory.init_nil_memory()
        |> PreMemory.set_access(a_0(), 1, :read)
        |> PreMemory.write(a_0(), test_data)

        |> PreMemory.finalize()

      machine = %Integrated{
        memory: source_memory,
        program: "program"
      }

      context = %{context | m: %{1 => machine}}

      # r7: machine ID, r8: dest offset, r9: source offset, r10: length
      registers = %Registers{
        r7: 1,
        r8: a_0(),
        r9: a_0(),
        r10: byte_size(test_data)
      }

      {:ok,
       memory: memory,
       context: context,
       machine: machine,
       gas: gas,
       registers: registers,
       test_data: test_data}
    end

    test "returns WHO when machine doesn't exist", %{
      memory: memory,
      context: context,
      gas: gas,
      registers: registers
    } do
      # Set r7 to non-existent machine ID
      registers = %{registers | r7: 999}
      who = who()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^who},
               memory: ^memory,
               context: ^context
             } = Refine.peek(gas, registers, memory, context)
    end

    test "returns OOB when source (aka machine) memory not readable", %{
      memory: memory,
      context: context,
      machine: machine,
      gas: gas,
      registers: registers
    } do
      # Make source memory unreadable at read location
      machine = %{
        machine
        | memory: Memory.set_access(machine.memory, registers.r9, registers.r10, nil)
      }

      context = %{context | m: %{1 => machine}}
      oob = oob()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^oob},
               memory: ^memory,
               context: ^context
             } = Refine.peek(gas, registers, memory, context)
    end

    test "panic and untouched everything when destination memory not writable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      # Make destination memory unwritable
      memory = Memory.set_access(%Memory{}, registers.r8, registers.r10, :read)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } = Refine.peek(gas, registers, memory, context)
    end

    test "successful peek with valid parameters", %{
      memory: memory,
      context: context,
      gas: gas,
      registers: registers,
      test_data: test_data
    } do
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^ok},
               memory: memory_,
               context: ^context
             } = Refine.peek(gas, registers, memory, context)

      assert Memory.read!(memory_, registers.r8, registers.r10) == test_data
    end

    test "out of gas", %{
      memory: memory,
      context: context,
      registers: registers
    } do
      assert %{
               exit_reason: :out_of_gas,
               registers: ^registers,
               memory: ^memory,
               context: ^context,
               gas: 0
             } = Refine.peek(8, registers, memory, context)
    end
  end
end
