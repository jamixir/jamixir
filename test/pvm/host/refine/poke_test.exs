defmodule PVM.Host.Refine.PokeTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Host.Refine.Context, ChildVm, Registers}
  import PVM.Constants.HostCallResult
  import Pvm.Native
  import PVM.TestHelpers

  describe "poke/4" do
    test "returns WHO when machine doesn't exist" do
      test_data = String.duplicate("A", 32)
      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      memory_write(memory_ref, a_0(), test_data)
      context = %Context{m: %{1 => new_test_machine()}}
      gas = 100
      registers =
        Registers.new(%{7 => 999, 8 => a_0(), 9 => a_0(), 10 => byte_size(test_data)})

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Refine.poke(gas, registers, memory_ref, context)

      assert registers_[7] == who()
    end

    test "panics when source (host) memory is not readable" do
      machine = new_test_machine()
      memory_ref = build_memory()
      # No read access at source
      set_memory_access(memory_ref, a_0(), 32, 0)
      context = %Context{m: %{1 => machine}}
      gas = 100
      registers =
        Registers.new(%{7 => 1, 8 => a_0(), 9 => a_0(), 10 => 32})

      assert %{exit_reason: :panic, registers: registers_, context: ^context} =
               Refine.poke(gas, registers, memory_ref, context)

      assert registers_[7] == 1
    end

    test "returns OOB when destination (child VM) memory is not writable" do
      # Machine exists but has no write access at dest offset
      machine = new_test_machine()
      test_data = String.duplicate("A", 32)
      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      memory_write(memory_ref, a_0(), test_data)
      context = %Context{m: %{1 => machine}}
      gas = 100
      registers =
        Registers.new(%{7 => 1, 8 => a_0(), 9 => a_0(), 10 => byte_size(test_data)})

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Refine.poke(gas, registers, memory_ref, context)

      assert registers_[7] == oob()
    end

    test "returns OK and copies host memory into child VM at dest" do
      test_data = String.duplicate("A", 32)
      machine = machine_with_writable_dest_at_a0()
      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      memory_write(memory_ref, a_0(), test_data)
      context = %Context{m: %{1 => machine}}
      gas = 100
      registers =
        Registers.new(%{7 => 1, 8 => a_0(), 9 => a_0(), 10 => byte_size(test_data)})

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Refine.poke(gas, registers, memory_ref, context)

      assert registers_[7] == ok()

      assert {:ok, ^test_data} = ChildVm.read_memory(machine, a_0(), byte_size(test_data))
    end

    test "out of gas leaves context and registers unchanged" do
      machine = new_test_machine()
      test_data = String.duplicate("A", 32)
      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      memory_write(memory_ref, a_0(), test_data)
      context = %Context{m: %{1 => machine}}
      registers = Registers.new(%{7 => 1, 8 => a_0(), 9 => a_0(), 10 => 32})

      assert %{
               exit_reason: :out_of_gas,
               registers: ^registers,
               context: ^context,
               gas: 0
             } = Refine.poke(8, registers, memory_ref, context)
    end
  end
end
