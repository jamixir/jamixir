defmodule PVM.Host.Refine.Internal.PeekTest do
  use ExUnit.Case
  alias PVM.Host.Refine.Internal
  alias PVM.{Memory, RefineContext, Integrated}
  import PVM.Constants.HostCallResult

  describe "peek_pure/3" do
    setup do
      source_memory = %Memory{}
      {:ok, source_memory} = Memory.write(source_memory, 0, "test_data")

      machine = %Integrated{
        memory: source_memory,
        program: "program"
      }

      context = %RefineContext{m: %{1 => machine}}
      memory = %Memory{}
      registers = List.duplicate(0, 13)

      {:ok, memory: memory, context: context, registers: registers, machine: machine}
    end

    test "returns WHO when machine doesn't exist", %{
      memory: memory,
      context: context,
      registers: registers
    } do
      registers =
        registers
        # non-existent machine ID
        |> List.replace_at(7, 999)
        # source offset
        |> List.replace_at(8, 0)
        # size
        |> List.replace_at(9, 32)
        # destination offset
        |> List.replace_at(10, 100)

      {new_registers, new_memory, new_context} =
        Internal.peek_pure(registers, memory, context)

      assert Enum.at(new_registers, 7) == who()
      assert new_memory == memory
      assert new_context == context
    end

    test "returns OOB when source memory read fails", %{
      memory: memory,
      context: context,
      registers: registers,
      machine: machine
    } do
      # Make source memory unreadable
      machine = %{machine | memory: Memory.set_access(machine.memory, 0, 32, nil)}
      context = %{context | m: %{1 => machine}}

      registers =
        registers
        # existing machine ID
        |> List.replace_at(7, 1)
        # source offset
        |> List.replace_at(8, 0)
        # size
        |> List.replace_at(9, 32)
        # destination offset
        |> List.replace_at(10, 100)

      {new_registers, new_memory, new_context} =
        Internal.peek_pure(registers, memory, context)

      assert Enum.at(new_registers, 7) == oob()
      assert new_memory == memory
      assert new_context == context
    end

    test "returns OOB when destination memory write fails", %{
      memory: memory,
      context: context,
      registers: registers
    } do
      # Make destination memory unwritable
      memory = Memory.set_access(memory, 100, 32, :read)

      registers =
        registers
        # existing machine ID
        |> List.replace_at(7, 1)
        # source offset
        |> List.replace_at(8, 0)
        # size
        |> List.replace_at(9, 32)
        # destination offset
        |> List.replace_at(10, 100)

      {new_registers, new_memory, new_context} =
        Internal.peek_pure(registers, memory, context)

      assert Enum.at(new_registers, 7) == oob()
      assert new_memory == memory
      assert new_context == context
    end

    test "successful peek with valid parameters", %{
      memory: memory,
      context: context,
      registers: registers,
      machine: machine
    } do
      test_data = "test_data"

      registers =
        registers
        # existing machine ID
        |> List.replace_at(7, 1)
        # destination offset
        |> List.replace_at(8, 100)
        # source offset
        |> List.replace_at(9, 0)
        # size
        |> List.replace_at(10, byte_size(test_data))

      machine = %{machine | memory: Memory.write(machine.memory, 0, test_data) |> elem(1)}
      context = %{context | m: %{1 => machine}}

      {new_registers, new_memory, new_context} =
        Internal.peek_pure(registers, memory, context)

      assert new_registers == List.replace_at(registers, 7, ok())

      # Verify data was copied correctly
      {:ok, ^test_data} = Memory.read(new_memory, 100, byte_size(test_data))

      assert new_context == context
    end
  end
end
