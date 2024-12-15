defmodule PVM.Host.Refine.MachineTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Refine.Context, Integrated, Registers}
  import PVM.Constants.HostCallResult

  describe "machine_pure/3" do
    test "returns OOB when memory read fails" do
      registers = %Registers{r7: 100, r8: 32, r9: 0}
      gas = 100

      # Make memory unreadable
      memory = Memory.set_access(%Memory{}, 100, 32, nil)

      {_exit_reason, %{registers: new_registers, memory: new_memory}, new_context} =
        Refine.machine(gas, registers, memory, %Context{})

      assert new_registers.r7 == oob()
      assert new_memory == memory
      assert new_context == %Context{}
    end

    test "successful machine creation with valid parameters" do
      test_program = "test_program"
      {:ok, memory} = Memory.write(%Memory{}, 0, test_program)
      gas = 100
      registers = %Registers{r7: 0, r8: byte_size(test_program), r9: 42}

      {_exit_reason, %{registers: new_registers, memory: new_memory}, new_context} =
        Refine.machine(gas, registers, memory, %Context{})

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
      context = %Context{
        m: %{
          2 => %Integrated{program: "prog2"},
          3 => %Integrated{program: "prog3"}
        }
      }

      test_program = "new_program"
      {:ok, memory} = Memory.write(%Memory{}, 0, test_program)
      gas = 100
      registers = %Registers{r7: 0, r8: byte_size(test_program), r9: 0}

      {_exit_reason, %{registers: new_registers}, new_context} =
        Refine.machine(gas, registers, memory, context)

      # Should return ID 1 (lowest available)
      assert new_registers.r7 == 1
      assert map_size(new_context.m) == 3

      # Verify machine state
      assert %Integrated{program: ^test_program} =
               Map.get(new_context.m, 1)
    end
  end
end
