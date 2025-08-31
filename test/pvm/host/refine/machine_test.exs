defmodule PVM.Host.Refine.MachineTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Integrated, Registers, PreMemory}
  use PVM.Instructions
  import PVM.Constants.HostCallResult
  import PVM.Memory.Constants

  describe "machine/4" do
    setup do
      context = %Context{}
      gas = 100

      # r7: program start, r8: program length, r9: initial counter
      test_program = PVM.Encoder.encode_program(<<1, 1, 1, 1, 1, 1, 1, 1>>, <<255>>, {}, 1)

      registers = Registers.new(%{
        7 => min_allowed_address(),
        8 => byte_size(test_program),
        9 => 42
      })

      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.set_access(min_allowed_address(), 1, :write)
        |> PreMemory.write(min_allowed_address(), test_program)
        |> PreMemory.finalize()

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
      memory = Memory.set_access(memory, registers[7], registers[8], nil)

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
               registers: registers_,
               memory: ^memory,
               context: context_
             } = Refine.machine(gas, registers, memory, context)
      assert registers_[7] == 0

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
               registers: registers_,
               memory: ^memory,
               context: context_
             } = Refine.machine(gas, registers, memory, context)

      assert registers_[7] == 1

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
               registers: registers_,
               memory: ^memory,
               context: context_
             } = Refine.machine(gas, registers, memory, context)

      # Verify new machine was added with ID 4

      assert registers_[7] == 4

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

    test "returns {:continue, huh()} when program is invalid", %{
      context: context,
      gas: gas,
      test_program: test_program,
      memory: memory
    } do
      test_program = <<40, 30, 20>> <> test_program

      registers = Registers.new(%{
        7 => 0x1_0000,
        8 => byte_size(test_program),
        9 => 42
      })

      memory = Memory.write!(memory, registers[7], test_program)
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: ^context
             } = Refine.machine(gas, registers, memory, context)

      assert registers_[7] == huh
    end
  end
end
