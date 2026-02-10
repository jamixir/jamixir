defmodule PVM.TestHelpers do
  @moduledoc """
  Helper functions for testing PVM functionality with Rust child VMs.
  Shared across host/refine tests (peek, poke, invoke, pages) and child_vm_test.
  """

  import PVM.Memory.Constants

  alias PVM.ChildVm

  def a_0, do: min_allowed_address()

  @page_size page_size()

  def minimal_program do
    program = <<0>>
    bitmask = <<0b1>>
    PVM.Encoder.encode_program(program, bitmask, {}, 1)
  end

  def new_test_machine do
    case ChildVm.new(minimal_program(), 0) do
      %ChildVm{} = m -> m
      {:error, reason} -> raise "ChildVm.new failed: #{inspect(reason)}"
    end
  end

  def machine_with_memory_at_a0(data) do
    machine = new_test_machine()
    page_index = div(a_0(), @page_size)
    :ok = ChildVm.set_memory_access(machine, page_index, 1, 3)
    :ok = ChildVm.write_memory(machine, a_0(), data)
    :ok = ChildVm.set_memory_access(machine, page_index, 1, 1)
    machine
  end

  def machine_with_writable_dest_at_a0 do
    machine = new_test_machine()
    page_index = div(a_0(), @page_size)
    :ok = ChildVm.set_memory_access(machine, page_index, 1, 3)
    machine
  end

  def load_imm_64_then_trap_program(reg_index, value) do
    load_imm_64 = <<20, reg_index, value::64-little>>
    trap = <<0>>
    program = load_imm_64 <> trap
    bitmask = <<0b1001>>
    PVM.Encoder.encode_program(program, bitmask, {}, 1)
  end

  def panic_program do
    program = <<1, 1, 1, 0, 0>>
    bitmask = <<0b11111>>
    PVM.Encoder.encode_program(program, bitmask, {}, 1)
  end

  @halt_address 0xFFFF0000

  def halt_program do
    jump_ind = 50
    program = <<jump_ind, 1, 0::32-little>>
    bitmask = <<0b1>>
    PVM.Encoder.encode_program(program, bitmask, {}, 1)
  end

  def halt_program_child_registers do
    List.duplicate(0, 13) |> List.replace_at(1, @halt_address)
  end

end
