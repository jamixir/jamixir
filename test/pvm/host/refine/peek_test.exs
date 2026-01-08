defmodule PVM.Host.Refine.PeekTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Host.Refine.Context, Integrated, Registers}
  import PVM.Constants.HostCallResult
  import PVM.Memory.Constants
  import Pvm.Native

  defp a_0, do: min_allowed_address()

  describe "peek/4" do
    setup do
      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 1, 3)

      context = %Context{}
      gas = 100

      test_data = String.duplicate("A", 32)

      source_memory_ref = build_memory()
      set_memory_access(source_memory_ref, a_0(), byte_size(test_data), 3)
      memory_write(source_memory_ref, a_0(), test_data)

      machine = %Integrated{memory: source_memory_ref, program: "program"}

      context = %{context | m: %{1 => machine}}

      # r7: machine ID, r8: dest offset, r9: source offset, r10: length
      registers =
        Registers.new(%{
          7 => 1,
          8 => a_0(),
          9 => a_0(),
          10 => byte_size(test_data)
        })

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

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Refine.peek(gas, registers, memory_ref, context)

      assert registers_[7] == who
    end

    test "returns OOB when source (aka machine) memory not readable", %{
      memory_ref: memory_ref,
      context: context,
      machine: machine,
      gas: gas,
      registers: registers
    } do
      # Make source memory unreadable at read location
      set_memory_access(machine.memory, registers[9], registers[10], 0)

      context = %{context | m: %{1 => machine}}
      oob = oob()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Refine.peek(gas, registers, memory_ref, context)

      assert registers_[7] == oob
    end

    test "panic and untouched everything when destination memory not writable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      # Make destination memory unwritable
      memory_ref = build_memory()
      set_memory_access(memory_ref, registers[8], registers[10], 1)

      assert %{exit_reason: :panic, registers: ^registers, context: ^context} =
               Refine.peek(gas, registers, memory_ref, context)
    end

    test "successful peek with valid parameters", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      registers: registers,
      test_data: test_data
    } do
      ok = ok()

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Refine.peek(gas, registers, memory_ref, context)

      {:ok, ^test_data} = memory_read(memory_ref, registers[8], registers[10])
      assert registers_[7] == ok
    end

    test "out of gas", %{
      memory_ref: memory_ref,
      context: context,
      registers: registers
    } do
      assert %{
               exit_reason: :out_of_gas,
               registers: ^registers,
               context: ^context,
               gas: 0
             } = Refine.peek(8, registers, memory_ref, context)
    end
  end
end
