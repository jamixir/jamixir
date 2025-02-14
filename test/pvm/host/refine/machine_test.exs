defmodule PVM.Host.Refine.MachineTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Integrated, Registers}

  describe "machine/4" do
    setup do
      memory = %Memory{}
      context = %Context{}
      gas = 100

      # r7: program start, r8: program length, r9: initial counter
      registers = %Registers{
        r7: 0x1_0000,
        r8: 32,
        r9: 42
      }

      test_program = String.duplicate("A", 32)
      memory = Memory.write!(memory, registers.r7, test_program)

      {:ok,
       memory: memory,
       context: context,
       gas: gas,
       registers: registers,
       test_program: test_program}
    end

    test "returns {:panic, w7} when memory not readable", %{
      memory: memory,
      context: context,
      gas: gas,
      registers: registers
    } do
      # Make memory unreadable at program location
      memory = Memory.set_access(memory, registers.r7, registers.r8, nil)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } = Refine.machine(gas, registers, memory, context)
    end

    test "creates new machine with ID 0 in empty context", %{
      memory: memory,
      context: context,
      gas: gas,
      registers: registers,
      test_program: test_program
    } do
      assert %{
               exit_reason: :continue,
               registers: %{r7: 0},
               memory: ^memory,
               context: context_
             } = Refine.machine(gas, registers, memory, context)

      # Verify new machine state
      assert %{0 => machine} = context_.m

      assert %Integrated{
               program: ^test_program,
               counter: 42,
               memory: %Memory{}
             } = machine
    end

    test "assigns lowest available ID when machines exist", %{
      memory: memory,
      gas: gas,
      registers: registers,
      test_program: test_program
    } do
      # Create context with machines 0 and 2
      context = %Context{
        m: %{
          0 => %Integrated{program: "existing0"},
          2 => %Integrated{program: "existing2"}
        }
      }

      assert %{
               exit_reason: :continue,
               registers: %{r7: 1},
               memory: ^memory,
               context: context_
             } = Refine.machine(gas, registers, memory, context)

      assert %{
               0 => %Integrated{program: "existing0"},
               2 => %Integrated{program: "existing2"},
               1 => %Integrated{
                 program: ^test_program,
                 counter: 42,
                 memory: %Memory{}
               }
             } = context_.m
    end

    test "assigns correct ID with consecutive machine IDs", %{
      memory: memory,
      gas: gas,
      registers: registers,
      test_program: test_program
    } do
      # Create context with machines 0,1,2,3
      context = %Context{
        m: %{
          0 => %Integrated{program: "existing0"},
          1 => %Integrated{program: "existing1"},
          2 => %Integrated{program: "existing2"},
          3 => %Integrated{program: "existing3"}
        }
      }

      assert %{
               exit_reason: :continue,
               registers: %{r7: 4},
               memory: ^memory,
               context: context_
             } = Refine.machine(gas, registers, memory, context)

      # Verify new machine was added with ID 4

      assert %{
               0 => %Integrated{program: "existing0"},
               1 => %Integrated{program: "existing1"},
               2 => %Integrated{program: "existing2"},
               3 => %Integrated{program: "existing3"},
               4 => %Integrated{
                 program: ^test_program,
                 counter: 42,
                 memory: %Memory{}
               }
             } = context_.m
    end
  end
end
