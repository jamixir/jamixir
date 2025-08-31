defmodule PVM.Host.Refine.InvokeTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Integrated, Registers, Utils.ProgramUtils, PreMemory}
  import PVM.Constants.{HostCallResult, InnerPVMResult}
  import Util.Hex
  import PVM.Memory.Constants

  describe "invoke/4" do
    setup do
      # Program that sets registers [1,2,3] to [30,11,10] and panics
      program =
        decode16!(
          "00012633010033020133030a3305020156120a14c3520452140008be12010183220128ee3d010300010100000100000100000100000101000000010000010000000100000101000001000100000000"
        )

      # Create and encode the halt program
      {halt_program, halt_bitmask} = ProgramUtils.create_halt_program()
      encoded_halt_program = PVM.Encoder.encode_program(halt_program, halt_bitmask, {}, 1)

      context = %Context{
        m: %{
          1 => %Integrated{
            program: program
          },
          2 => %Integrated{
            program: encoded_halt_program
          }
        }
      }

      # gas
      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.set_access(min_allowed_address(), page_size() + 1, :write)
        |> PreMemory.finalize()
        |> Memory.write!(0x1_1000, <<100::64-little>>)

      gas = 100

      # Base registers setup
      registers = Registers.new(%{
        # machine ID
        7 => 1,
        # output address (second usable page)
        8 => 0x1_1000
      })

      {:ok, memory: memory, context: context, gas: gas, registers: registers}
    end

    test "returns panic when memory not readable at input", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory
    } do
      memory = Memory.set_access(memory, registers[8], 1, nil)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } = Refine.invoke(gas, registers, memory, context)
    end

    test "returns WHO when machine doesn't exist", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory
    } do
      registers = %{registers | r: put_elem(registers.r, 7, 999)}
      who = who()
      w8 = registers[8]

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: ^context
             } = Refine.invoke(gas, registers, memory, context)

      assert registers_[7] == who
      assert registers_[8] == w8
    end

    test "executes program successfully", %{
      context: context,
      memory: memory,
      gas: gas,
      registers: registers
    } do
      halt = halt()
      registers = %{registers | r: put_elem(registers.r, 7, 2)}

      registers_for_inner_execution =
        for x <- [42, 17, 83, 95, 29, 64, 71, 38, 56, 92, 13, 77],
            into: <<>>,
            do: <<x::64-little>>

      memory = Memory.write!(memory, registers[8] + 8, registers_for_inner_execution)

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: context_
             } = Refine.invoke(gas, registers, memory, context)

      # Read the execution results from memory
      {:ok, _gas_bytes} = Memory.read(memory_, registers[8], 8)

      # Verify machine state in context
      machine = Map.get(context_.m, 2)
      # Should be at position 0 after halt
      assert machine.counter == 0
      assert registers_[7] == halt

      assert {:ok, ^registers_for_inner_execution} =
               Memory.read(memory_, registers[8] + 8, 12 * 8)
    end
  end
end
