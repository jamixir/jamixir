defmodule PVM.Host.Refine.MachineTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Host.Refine.Context, Integrated, Registers}
  use PVM.Instructions
  import PVM.Constants.HostCallResult
  import PVM.Memory.Constants
  import Pvm.Native

  describe "machine/4" do
    setup do
      context = %Context{}
      gas = 100

      # r7: program start, r8: program length, r9: initial counter
      test_program = PVM.Encoder.encode_program(<<1, 1, 1, 1, 1, 1, 1, 1>>, <<255>>, {}, 1)

      registers =
        Registers.new(%{
          7 => min_allowed_address(),
          8 => byte_size(test_program),
          9 => 42
        })

      memory_ref = build_memory()
      set_memory_access(memory_ref, min_allowed_address(), byte_size(test_program), 3)
      memory_write(memory_ref, min_allowed_address(), test_program)

      {:ok,
       memory_ref: memory_ref,
       context: context,
       gas: gas,
       registers: registers,
       test_program: test_program}
    end

    test "returns {:panic, w7} when memory not readable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      # Make memory unreadable at program location
      memory_ref = build_memory()

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               context: ^context
             } = Refine.machine(gas, registers, memory_ref, context)
    end

    test "creates new machine with ID 0 in empty context", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      registers: registers,
      test_program: test_program
    } do
      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: context_
             } = Refine.machine(gas, registers, memory_ref, context)

      assert registers_[7] == 0

      # Verify new machine state
      assert %{0 => machine} = context_.m

      assert %Integrated{
               program: ^test_program,
               counter: 42
             } = machine
    end

    test "assigns lowest available ID when machines exist", %{
      memory_ref: memory_ref,
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
               context: context_
             } = Refine.machine(gas, registers, memory_ref, context)

      assert registers_[7] == 1

      assert %{
               0 => %Integrated{program: "existing0"},
               2 => %Integrated{program: "existing2"},
               1 => %Integrated{
                 program: ^test_program,
                 counter: 42
               }
             } = context_.m
    end

    test "assigns correct ID with consecutive machine IDs", %{
      memory_ref: memory_ref,
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
               context: context_
             } = Refine.machine(gas, registers, memory_ref, context)

      # Verify new machine was added with ID 4

      assert registers_[7] == 4

      assert %{
               0 => %Integrated{program: "existing0"},
               1 => %Integrated{program: "existing1"},
               2 => %Integrated{program: "existing2"},
               3 => %Integrated{program: "existing3"},
               4 => %Integrated{
                 program: ^test_program,
                 counter: 42
               }
             } = context_.m
    end

    test "returns {:continue, huh()} when program is invalid", %{
      context: context,
      gas: gas,
      test_program: test_program,
      memory_ref: memory_ref
    } do
      test_program = <<40, 30, 20>> <> test_program

      registers =
        Registers.new(%{
          7 => 0x1_0000,
          8 => byte_size(test_program),
          9 => 42
        })

      memory_write(memory_ref, registers[7], test_program)
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Refine.machine(gas, registers, memory_ref, context)

      assert registers_[7] == huh
    end
  end
end
