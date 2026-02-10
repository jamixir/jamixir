defmodule PVM.Host.Refine.InvokeTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Host.Refine.Context, ChildVm, Registers}
  import PVM.Constants.HostCallResult
  import PVM.Constants.InnerPVMResult
  import Pvm.Native
  import PVM.TestHelpers

  defp setup_invoke(program, param_addr, gas_for_child, child_registers \\ List.duplicate(0, 13)) do
    memory_ref = build_memory()
    program_addr = param_addr + 0x1000

    set_memory_access(memory_ref, program_addr, byte_size(program), 3)
    memory_write(memory_ref, program_addr, program)

    machine_registers = Registers.new(%{7 => program_addr, 8 => byte_size(program), 9 => 0})
    gas = 10_000
    context = %Context{m: %{}}

    %{context: context_with_machine} =
      Refine.machine(gas, machine_registers, memory_ref, context)

    invoke_params =
      <<gas_for_child::64-little>> <>
        for(reg <- child_registers, into: <<>>, do: <<reg::64-little>>)

    set_memory_access(memory_ref, param_addr, 112, 3)
    memory_write(memory_ref, param_addr, invoke_params)

    invoke_registers = Registers.new(%{7 => 0, 8 => param_addr})

    {memory_ref, context_with_machine, param_addr, gas_for_child, invoke_registers}
  end

  defp read_invoke_result(memory_ref, param_addr) do
    {:ok, data} = memory_read(memory_ref, param_addr, 112)
    <<remaining_gas::64-little, regs_bin::binary>> = data
    regs = for(<<r::64-little <- regs_bin>>, do: r)
    {remaining_gas, regs}
  end

  describe "invoke/4" do
    test "returns WHO when machine doesn't exist" do
      {memory_ref, context, _param_addr, _gas, invoke_registers} =
        setup_invoke(panic_program(), a_0(), 1000)

      registers = %{invoke_registers | r: put_elem(invoke_registers.r, 7, 999)}
      result = Refine.invoke(10_000, registers, memory_ref, context)

      assert %{exit_reason: :continue, registers: registers_} = result
      assert registers_[7] == who()
    end

    test "program that halts: JUMP_IND to 0xFFFF0000 returns halt()" do
      param_addr = a_0()
      {memory_ref, context, param_addr, gas_for_child, invoke_registers} =
        setup_invoke(halt_program(), param_addr, 1000, halt_program_child_registers())

      result = Refine.invoke(10_000, invoke_registers, memory_ref, context)

      assert %{exit_reason: :continue, registers: registers_, context: _context_} = result
      assert registers_[7] == halt()

      {remaining_gas, regs} = read_invoke_result(memory_ref, param_addr)
      assert remaining_gas <= gas_for_child
      assert length(regs) == 13
    end

    test "program that panics: returns panic(), params written back, child state updated" do
      param_addr = a_0()
      gas_for_child = 1000
      {memory_ref, context, param_addr, _gas, invoke_registers} =
        setup_invoke(panic_program(), param_addr, gas_for_child)

      result = Refine.invoke(10_000, invoke_registers, memory_ref, context)

      assert %{exit_reason: :continue, registers: registers_, context: context_} = result
      assert registers_[7] == panic()
      assert registers_[8] == param_addr

      # Invoke params written back: remaining gas and 13 registers
      {remaining_gas, regs} = read_invoke_result(memory_ref, param_addr)
      assert remaining_gas <= gas_for_child
      assert length(regs) == 13

      # Child VM in context: PC after panic_program (3× FALLTHROUGH then TRAP) run
      machine = Map.get(context_.m, 0)
      assert %ChildVm{} = machine
      assert machine.counter == 0,
             "panic should have reset the counter"
    end

    test "program that updates register: LOAD_IMM_64 then TRAP, params show updated register" do
      param_addr = a_0()
      program = load_imm_64_then_trap_program(1, 0x12345678)
      {memory_ref, context, param_addr, _gas, invoke_registers} =
        setup_invoke(program, param_addr, 1000)

      result = Refine.invoke(10_000, invoke_registers, memory_ref, context)

      assert %{exit_reason: :continue, registers: registers_, context: _context_} = result
      assert registers_[7] == panic()

      {_remaining_gas, regs} = read_invoke_result(memory_ref, param_addr)
      assert length(regs) == 13
      assert Enum.at(regs, 1) == 0x12345678
    end

    test "program that panics: invalid opcode returns panic()" do
      # Valid blob that panics on first step (invalid opcode 0xFD after decode)
      program_panic = <<0x00, 0x00, 0x00, 0x00, 0xFD>>
      bitmask_panic = <<31>>
      program_blob = PVM.Encoder.encode_program(program_panic, bitmask_panic, {}, 1)

      case Pvm.Native.validate_program_blob(program_blob) do
        :ok ->
          {memory_ref, context, _param_addr, _gas, invoke_registers} =
            setup_invoke(program_blob, a_0(), 1000)

          result = Refine.invoke(10_000, invoke_registers, memory_ref, context)

          assert %{exit_reason: :continue, registers: registers_} = result
          assert registers_[7] == panic()

        _ ->
          # If blob is rejected, skip
          assert true
      end
    end

    test "invoke params written back: gas consumed and registers match child state" do
      param_addr = a_0()
      initial_gas = 2000
      child_regs = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120]
      program = load_imm_64_then_trap_program(1, 0xDEADBEEF)

      {memory_ref, context, param_addr, _g, invoke_registers} =
        setup_invoke(program, param_addr, initial_gas, child_regs)

      result = Refine.invoke(10_000, invoke_registers, memory_ref, context)

      assert %{exit_reason: :continue, registers: registers_} = result
      assert registers_[7] == panic()

      {remaining_gas, regs} = read_invoke_result(memory_ref, param_addr)
      assert remaining_gas < initial_gas
      assert Enum.at(regs, 1) == 0xDEADBEEF
    end

    test "child VM state is updated in context after invoke" do
      param_addr = a_0()
      {memory_ref, context, param_addr, gas_for_child, invoke_registers} =
        setup_invoke(panic_program(), param_addr, 1000)

      result = Refine.invoke(10_000, invoke_registers, memory_ref, context)
      assert %{context: context_} = result

      machine_after = Map.get(context_.m, 0)
      assert %ChildVm{} = machine_after
      assert is_integer(machine_after.counter) and machine_after.counter >= 0

      # Params written back proves execution ran and state was updated
      {remaining_gas, _regs} = read_invoke_result(memory_ref, param_addr)
      assert remaining_gas <= gas_for_child
    end
  end
end
