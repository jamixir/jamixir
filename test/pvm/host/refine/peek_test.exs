defmodule PVM.Host.Refine.PeekTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Host.Refine.Context, Registers}
  import PVM.Constants.HostCallResult
  import Pvm.Native
  import PVM.TestHelpers

  describe "peek/4" do
    test "returns WHO when machine doesn't exist" do
      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      context = %Context{m: %{1 => new_test_machine()}}
      gas = 100
      registers =
        Registers.new(%{7 => 999, 8 => a_0(), 9 => a_0(), 10 => 32})

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Refine.peek(gas, registers, memory_ref, context)

      assert registers_[7] == who()
    end

    test "returns OOB when source (child VM) memory is not readable" do
      # Machine exists but has no read access at source offset
      machine = new_test_machine()
      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      context = %Context{m: %{1 => machine}}
      gas = 100
      registers =
        Registers.new(%{7 => 1, 8 => a_0(), 9 => a_0(), 10 => 32})

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Refine.peek(gas, registers, memory_ref, context)

      assert registers_[7] == oob()
    end

    test "panics when destination (host) memory is not writable" do
      machine = machine_with_memory_at_a0(String.duplicate("A", 32))
      memory_ref = build_memory()
      # Dest range readable but not writable
      set_memory_access(memory_ref, a_0(), 32, 1)
      context = %Context{m: %{1 => machine}}
      gas = 100
      registers =
        Registers.new(%{7 => 1, 8 => a_0(), 9 => a_0(), 10 => 32})

      assert %{exit_reason: :panic, registers: registers_, context: ^context} =
               Refine.peek(gas, registers, memory_ref, context)

      assert registers_[7] == 1
    end

    test "returns OK and copies child VM memory to host at dest" do
      test_data = String.duplicate("A", 32)
      machine = machine_with_memory_at_a0(test_data)
      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      context = %Context{m: %{1 => machine}}
      gas = 100
      registers =
        Registers.new(%{7 => 1, 8 => a_0(), 9 => a_0(), 10 => byte_size(test_data)})

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Refine.peek(gas, registers, memory_ref, context)

      assert registers_[7] == ok()

      assert {:ok, ^test_data} = memory_read(memory_ref, a_0(), byte_size(test_data))
    end

    test "out of gas leaves context and registers unchanged" do
      machine = new_test_machine()
      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      context = %Context{m: %{1 => machine}}
      registers = Registers.new(%{7 => 1, 8 => a_0(), 9 => a_0(), 10 => 32})

      assert %{
               exit_reason: :out_of_gas,
               registers: ^registers,
               context: ^context,
               gas: 0
             } = Refine.peek(8, registers, memory_ref, context)
    end
  end
end
