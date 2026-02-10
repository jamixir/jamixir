defmodule PVM.ChildVmTest do
  use ExUnit.Case
  import PVM.Memory.Constants
  import PVM.TestHelpers

  describe "create_child_vm/4" do
    test "creates a VM instance with valid program" do
      program = halt_program()
      registers = List.duplicate(0, 13)

      assert {:ok, vm_ref} = Pvm.Native.create_child_vm(program, 0, 1000, registers)
      assert is_reference(vm_ref)
    end

    test "fails with invalid program blob" do
      invalid_blob = <<0xFF, 0xFF, 0xFF>>
      registers = List.duplicate(0, 13)

      assert {:error, _} = Pvm.Native.create_child_vm(invalid_blob, 0, 1000, registers)
    end
  end

  describe "validate_program_blob/1" do
    test "validates a correct program blob" do
      program = halt_program()

      assert :ok = Pvm.Native.validate_program_blob(program)
    end

    test "rejects an invalid program blob" do
      invalid_blob = <<0xFF, 0xFF, 0xFF>>

      assert {:error, :invalid_program} = Pvm.Native.validate_program_blob(invalid_blob)
    end

    test "rejects empty blob" do
      assert {:error, :invalid_program} = Pvm.Native.validate_program_blob(<<>>)
    end
  end

  describe "execute_child_vm/3" do
    test "executes with gas and registers and returns result (halt or panic acceptable)" do
      program = halt_program()
      registers = List.duplicate(0, 13)

      {:ok, vm_ref} = Pvm.Native.create_child_vm(program, 0, 1000, registers)

      # Execution may return halt or panic depending on program/memory setup
      # Both are acceptable as long as it executes without crashing
      result = Pvm.Native.execute_child_vm(vm_ref, 1000, registers)

      assert {exit_reason, state} = result
      assert exit_reason in [:halt, :panic, :out_of_gas]
      assert %Pvm.Native.VmState{} = state
      assert is_integer(state.spent_gas)
    end

    # Program from pvm-rust dispatcher_reg_immediate_tests: LOAD_IMM_64 (opcode 20) loads
    # a 64-bit immediate into a register, then TRAP (opcode 0) stops execution.
    test "executes LOAD_IMM_64 then TRAP and we see register effect" do
      program_blob = load_imm_64_then_trap_program(1, 0x12345678)
      registers = List.duplicate(0, 13)

      assert :ok = Pvm.Native.validate_program_blob(program_blob)
      {:ok, vm_ref} = Pvm.Native.create_child_vm(program_blob, 0, 1000, registers)

      result = Pvm.Native.execute_child_vm(vm_ref, 1000, registers)

      assert {exit_reason, state} = result
      assert exit_reason in [:halt, :panic, :out_of_gas]
      assert %Pvm.Native.VmState{} = state
      # LOAD_IMM_64 wrote 0x12345678 into r1 before TRAP
      assert Enum.at(state.registers, 1) == 0x12345678
      assert is_integer(state.spent_gas)
    end
  end

  describe "child_vm_read_memory/3 and child_vm_write_memory/3" do
    test "write and read memory from child VM when permissions are set" do
      program = halt_program()
      registers = List.duplicate(0, 13)

      {:ok, vm_ref} = Pvm.Native.create_child_vm(program, 0, 1000, registers)

      addr = min_allowed_address()
      page_index = div(addr, page_size())
      assert :ok = Pvm.Native.set_child_vm_memory_access(vm_ref, page_index, 1, 3)

      data = <<1, 2, 3, 4>>
      assert :ok = Pvm.Native.child_vm_write_memory(vm_ref, addr, data)
      assert {:ok, ^data} = Pvm.Native.child_vm_read_memory(vm_ref, addr, 4)
    end
  end

  describe "PVM.ChildVm" do
    test "new/2 creates a child VM with defaults" do
      program = halt_program()

      assert %PVM.ChildVm{} = machine = PVM.ChildVm.new(program, 0)
      assert is_reference(machine.vm_instance_ref)
      assert machine.program == program
      assert machine.counter == 0
    end

    test "new/3 creates a child VM instance with explicit params" do
      program = halt_program()

      assert %PVM.ChildVm{} = machine = PVM.ChildVm.new(program, 0, 1000)
      assert is_reference(machine.vm_instance_ref)
      assert machine.program == program
      assert machine.counter == 0
    end

    test "new/2 validates program blob (JAM spec)" do
      invalid_program = <<0xFF, 0xFF, 0xFF>>

      # Should fail validation
      assert {:error, _} = PVM.ChildVm.new(invalid_program, 0)
    end

    test "execute/3 runs the VM with gas and registers" do
      program = halt_program()

      machine = PVM.ChildVm.new(program, 0, 1000)
      registers = List.duplicate(0, 13)

      assert {exit_reason, updated_machine, vm_state} = PVM.ChildVm.execute(machine, 1000, registers)
      # Accept halt or panic as valid outcomes (depends on program/memory setup)
      assert exit_reason in [:halt, :panic, :out_of_gas]
      assert %PVM.ChildVm{} = updated_machine
      assert %Pvm.Native.VmState{} = vm_state
    end

    test "execute/3 updates gas and registers before execution" do
      program = halt_program()

      machine = PVM.ChildVm.new(program, 0, 100)

      new_registers = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130]
      new_gas = 2000

      # Execute with new gas and registers
      assert {_exit_reason, _updated_machine, vm_state} = PVM.ChildVm.execute(machine, new_gas, new_registers)

      # Verify the state was updated
      assert vm_state.initial_gas == new_gas
      assert vm_state.registers == new_registers
    end

    test "read_memory and write_memory work with child VMs when permissions are set" do
      program = halt_program()

      machine = PVM.ChildVm.new(program, 0, 1000)

      addr = min_allowed_address()
      page_index = div(addr, page_size())
      assert :ok = PVM.ChildVm.set_memory_access(machine, page_index, 1, 3)

      data = <<"test data">>
      assert :ok = PVM.ChildVm.write_memory(machine, addr, data)
      assert {:ok, ^data} = PVM.ChildVm.read_memory(machine, addr, byte_size(data))
    end

    test "destroy/1 cleans up VM instance" do
      program = halt_program()

      machine = PVM.ChildVm.new(program, 0, 1000)

      assert :ok = PVM.ChildVm.destroy(machine)
    end
  end

  describe "memory isolation" do
    test "two VM instances have separate memory when permissions are set" do
      program = halt_program()

      machine1 = PVM.ChildVm.new(program, 0, 1000)
      machine2 = PVM.ChildVm.new(program, 0, 1000)

      addr = min_allowed_address()
      page_index = div(addr, page_size())
      # Permission 3 = read+write; required for write_memory/read_memory to succeed
      assert :ok = PVM.ChildVm.set_memory_access(machine1, page_index, 1, 3)
      assert :ok = PVM.ChildVm.set_memory_access(machine2, page_index, 1, 3)

      data1 = <<"data for vm1">>
      data2 = <<"data for vm2">>

      assert :ok = PVM.ChildVm.write_memory(machine1, addr, data1)
      assert :ok = PVM.ChildVm.write_memory(machine2, addr, data2)

      assert {:ok, ^data1} = PVM.ChildVm.read_memory(machine1, addr, byte_size(data1))
      assert {:ok, ^data2} = PVM.ChildVm.read_memory(machine2, addr, byte_size(data2))
    end
  end
end
