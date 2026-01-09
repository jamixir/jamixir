defmodule PVM.Host.Refine.PokeTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Host.Refine.Context, Integrated, Registers}
  import PVM.Constants.HostCallResult
  import PVM.Memory.Constants
  import Pvm.Native

  defp a_0, do: min_allowed_address()

  describe "poke/4" do
    setup do
      test_data = String.duplicate("A", 32)

      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), byte_size(test_data), 3)
      memory_write(memory_ref, a_0(), test_data)

      machine_memory_ref = build_memory()
      set_memory_access(machine_memory_ref, a_0(), byte_size(test_data), 3)

      machine = %Integrated{
        memory: machine_memory_ref,
        program: "program"
      }

      context = %Context{m: %{1 => machine}}

      # r7: machine ID, r8: source offset, r9: dest offset, r10: length
      registers = Registers.new(%{7 => 1, 8 => a_0(), 9 => a_0(), 10 => byte_size(test_data)})

      gas = 100

      {:ok,
       memory_ref: memory_ref,
       context: context,
       machine: machine,
       gas: gas,
       registers: registers,
       test_data: test_data}
    end

    test "returns WHO when machine doesn't exist", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      registers: registers
    } do
      # Set r7 to non-existent machine ID
      registers = %{registers | r: put_elem(registers.r, 7, 999)}
      who = who()

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Refine.poke(gas, registers, memory_ref, context)

      assert registers_[7] == who
    end

    test "panic and untouched everything when source memory not readable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      # Make source memory unreadable
      memory_ref = build_memory()
      set_memory_access(memory_ref, registers[8], registers[10], 0)

      assert %{exit_reason: :panic, registers: ^registers, context: ^context} =
               Refine.poke(gas, registers, memory_ref, context)
    end

    test "returns OOB when destination memory not writable", %{
      memory_ref: memory_ref,
      context: context,
      machine: machine,
      gas: gas,
      registers: registers
    } do
      # Make machine memory unwritable
      set_memory_access(machine.memory, registers[9], registers[10], 1)

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Refine.poke(gas, registers, memory_ref, context)

      assert registers_[7] == oob()
    end

    test "successful poke with valid parameters", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      registers: registers,
      test_data: test_data
    } do
      assert %{exit_reason: :continue, registers: registers_, context: context_} =
               Refine.poke(gas, registers, memory_ref, context)

      assert registers_[7] == ok()

      # Verify data was copied correctly to machine memory
      machine = Map.get(context_.m, 1)
      {:ok, ^test_data} = memory_read(machine.memory, registers[9], registers[10])
    end
  end
end
