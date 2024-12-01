defmodule PVM.Host.Refine.Internal.MachineTest do
  use ExUnit.Case
  alias PVM.Host.Refine.Internal
  alias PVM.{Memory, RefineContext, Integrated, Registers}
  import PVM.Constants.HostCallResult

  describe "machine_pure/3" do


    test "returns OOB when memory read fails" do
      registers = %Registers{r7: 100, r8: 32, r9: 0}

      # Make memory unreadable
      memory = Memory.set_access(%Memory{}, 100, 32, nil)

      {new_registers, new_memory, new_context} =
        Internal.machine_pure(registers, memory, %RefineContext{})

      assert new_registers.r7 == oob()
      assert new_memory == memory
      assert new_context == %RefineContext{}
    end

    test "successful machine creation with valid parameters" do
      test_program = "test_program"
      {:ok, memory} = Memory.write(%Memory{}, 0, test_program)

      registers = %Registers{r7: 0, r8: byte_size(test_program), r9: 42}

      {new_registers, new_memory, new_context} =
        Internal.machine_pure(registers, memory, %RefineContext{})

      # Should return machine ID 0 since context is empty
      assert new_registers.r7 == 0

      # Memory should be unchanged
      assert new_memory == memory

      # Context should have new machine
      assert map_size(new_context.m) == 1
      assert Map.has_key?(new_context.m, 0)

      # Verify machine state
      assert %Integrated{program: ^test_program, counter: 42, memory: %Memory{}} =
               Map.get(new_context.m, 0)
    end

    test "assigns lowest available ID when machines exist" do
      # Create context with machines 2 and 3
      context = %RefineContext{
        m: %{
            2 => %Integrated{program: "prog2"},
            3 => %Integrated{program: "prog3"}
        }
      }

      test_program = "new_program"
      {:ok, memory} = Memory.write(%Memory{}, 0, test_program)

      registers = %Registers{r7: 0, r8: byte_size(test_program), r9: 0}

      {new_registers, new_memory, new_context} =
        Internal.machine_pure(registers, memory, context)

      # Should return ID 1 (lowest available)
      assert new_registers.r7 == 1
      assert map_size(new_context.m) == 3

      # Verify machine state
      assert %Integrated{program: ^test_program} =
               Map.get(new_context.m, 1)
    end
  end
end
