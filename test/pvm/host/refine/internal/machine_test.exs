defmodule PVM.Host.Refine.Internal.MachineTest do
  use ExUnit.Case
  alias PVM.Host.Refine.Internal
  alias PVM.{Memory, RefineContext, Integrated}
  import PVM.Constants.HostCallResult

  describe "machine_pure/3" do
    setup do
      memory = %Memory{}
      context = %RefineContext{}
      registers = List.duplicate(0, 13)

      {:ok, memory: memory, context: context, registers: registers}
    end

    test "returns OOB when memory read fails", %{
      memory: memory,
      context: context,
      registers: registers
    } do
      registers =
        registers
        # p0 - program offset
        |> List.replace_at(7, 100)
        # pz - program size
        |> List.replace_at(8, 32)
        # i - initial counter
        |> List.replace_at(9, 0)

      # Make memory unreadable
      memory = Memory.set_access(memory, 100, 32, nil)

      {new_registers, new_memory, new_context} =
        Internal.machine_pure(registers, memory, context)

      assert Enum.at(new_registers, 7) == oob()
      assert new_memory == memory
      assert new_context == context
    end

    test "successful machine creation with valid parameters", %{
      memory: memory,
      context: context,
      registers: registers
    } do
      test_program = "test_program"
      {:ok, memory} = Memory.write(memory, 0, test_program)

      registers =
        registers
        # p0 - program offset
        |> List.replace_at(7, 0)
        # pz - program size
        |> List.replace_at(8, byte_size(test_program))
        # i - initial counter
        |> List.replace_at(9, 42)

      {new_registers, new_memory, new_context} =
        Internal.machine_pure(registers, memory, context)

      # Should return machine ID 0 since context is empty
      assert Enum.at(new_registers, 7) == 0

      # Memory should be unchanged
      assert new_memory == memory

      # Context should have new machine
      assert map_size(new_context.m) == 1
      assert Map.has_key?(new_context.m, 0)

      # Verify machine state
      assert %Integrated{program: ^test_program, counter: 42, memory: %Memory{}} =
               Map.get(new_context.m, 0)
    end

    test "assigns lowest available ID when machines exist", %{
      memory: memory,
      context: context,
      registers: registers
    } do
      # Create context with machines 2 and 3
      context = %{
        context
        | m: %{
            2 => %Integrated{program: "prog2"},
            3 => %Integrated{program: "prog3"}
          }
      }

      test_program = "new_program"
      {:ok, memory} = Memory.write(memory, 0, test_program)

      registers =
        registers
        # p0
        |> List.replace_at(7, 0)
        # pz
        |> List.replace_at(8, byte_size(test_program))
        # i
        |> List.replace_at(9, 0)

      {new_registers, new_memory, new_context} =
        Internal.machine_pure(registers, memory, context)

      # Should return ID 1 (lowest available)
      assert Enum.at(new_registers, 7) == 1
      assert map_size(new_context.m) == 3

      # Verify machine state
      assert %Integrated{program: ^test_program} =
               Map.get(new_context.m, 1)
    end
  end
end
