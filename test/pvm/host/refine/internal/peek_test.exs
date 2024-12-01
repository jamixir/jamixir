defmodule PVM.Host.Refine.Internal.PeekTest do
  use ExUnit.Case
  alias PVM.Host.Refine.Internal
  alias PVM.{Memory, RefineContext, Integrated, Registers}
  import PVM.Constants.HostCallResult

  describe "peek_pure/3" do
    setup do
      {:ok, source_memory} = Memory.write(%Memory{}, 0, "test_data")

      machine = %Integrated{
        memory: source_memory,
        program: "program"
      }

      context = %RefineContext{m: %{1 => machine}}

      {:ok, context: context, machine: machine}
    end

    test "returns WHO when machine doesn't exist", %{
      context: context,
      machine: machine
    } do
      registers = %Registers{r7: 999, r8: 0, r9: 32, r10: 100}

      {new_registers, new_memory, new_context} =
        Internal.peek_pure(registers, %Memory{}, context)

      assert new_registers.r7 == who()
      assert new_memory == %Memory{}
      assert new_context == context
    end

    test "returns OOB when source memory read fails", %{
      context: context,
      machine: machine
    } do
      # Make source memory unreadable
      machine = %{machine | memory: Memory.set_access(machine.memory, 0, 32, nil)}
      context = %{context | m: %{1 => machine}}

      registers = %Registers{r7: 1, r8: 0, r9: 32, r10: 100}

      {new_registers, new_memory, new_context} =
        Internal.peek_pure(registers, %Memory{}, context)

      assert new_registers.r7 == oob()
      assert new_memory == %Memory{}
      assert new_context == context
    end

    test "returns OOB when destination memory write fails", %{
      context: context,
      machine: machine
    } do
      # Make destination memory unwritable
      memory = Memory.set_access(%Memory{}, 100, 32, :read)

      registers = %Registers{r7: 1, r8: 0, r9: 32, r10: 100}

      {new_registers, new_memory, new_context} =
        Internal.peek_pure(registers, memory, context)

      assert new_registers.r7 == oob()
      assert new_memory == memory
      assert new_context == context
    end

    test "successful peek with valid parameters", %{
      context: context,
      machine: machine
    } do
      test_data = "test_data"

      registers = %Registers{r7: 1, r8: 100, r9: 0, r10: byte_size(test_data)}

      machine = %{machine | memory: Memory.write(machine.memory, 0, test_data) |> elem(1)}
      context = %{context | m: %{1 => machine}}

      {new_registers, new_memory, new_context} =
        Internal.peek_pure(registers, %Memory{}, context)

      assert new_registers.r7 == ok()

      # Verify data was copied correctly
      {:ok, ^test_data} = Memory.read(new_memory, 100, byte_size(test_data))

      assert new_context == context
    end
  end
end
