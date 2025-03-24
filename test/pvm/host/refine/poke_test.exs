defmodule PVM.Host.Refine.PokeTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Integrated, Registers, PreMemory}
  import PVM.Constants.HostCallResult
  import PVM.Memory.Constants

  defp a_0, do: min_allowed_address()

  describe "poke/4" do
    setup do
      test_data = String.duplicate("A", 32)

      pvm_memory =
        PreMemory.init_nil_memory()
        |> PreMemory.set_access(a_0(), 1, :read)
        |> PreMemory.write(a_0(), test_data)

        |> PreMemory.finalize()

      machine_memory =
        PreMemory.init_nil_memory()
        |> PreMemory.set_access(a_0(), 1, :write)

        |> PreMemory.finalize()

      machine = %Integrated{
        memory: machine_memory,
        program: "program"
      }

      context = %Context{m: %{1 => machine}}

      # r7: machine ID, r8: source offset, r9: dest offset, r10: length
      registers = %Registers{
        r7: 1,
        r8: a_0(),
        r9: a_0(),
        r10: byte_size(test_data)
      }

      gas = 100

      {:ok,
       memory: pvm_memory,
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
             } = Refine.poke(gas, registers, memory, context)
    end

    test "panic and untouched everything when source memory not readable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      # Make source memory unreadable
      memory = Memory.set_access(%Memory{}, registers.r8, registers.r10, nil)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } = Refine.poke(gas, registers, memory, context)
    end

    test "returns OOB when destination memory not writable", %{
      memory: memory,
      context: context,
      machine: machine,
      gas: gas,
      registers: registers
    } do
      # Make machine memory unwritable
      machine = %{
        machine
        | memory: Memory.set_access(machine.memory, registers.r9, registers.r10, :read)
      }

      context = %{context | m: %{1 => machine}}

      assert %{
               exit_reason: :continue,
               registers: %{r7: oob},
               memory: ^memory,
               context: ^context
             } = Refine.poke(gas, registers, memory, context)

      assert oob == oob()
    end

    test "successful poke with valid parameters", %{
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
               memory: ^memory,
               context: context_
             } = Refine.poke(gas, registers, memory, context)

      assert ok == ok()

      # Verify data was copied correctly to machine memory
      machine = Map.get(context_.m, 1)
      assert Memory.read!(machine.memory, registers.r9, registers.r10) == test_data
    end
  end
end
