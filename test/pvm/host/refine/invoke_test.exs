defmodule PVM.Host.Refine.InvokeTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Integrated, Registers, Utils.ProgramUtils, PreMemory}
  import PVM.Constants.{HostCallResult, InnerPVMResult}
  use Codec.Decoder
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
      encoded_halt_program = PVM.Encoder.encode_program(halt_program, halt_bitmask, [], 1)

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
      memory = PreMemory.init_nil_memory()
        |> PreMemory.set_access(min_allowed_address(), page_size() +1 , :write)
        |> PreMemory.resolve_overlaps()
        |> PreMemory.finalize()
        |> Memory.write!(0x1_1000, <<100::64-little>>)
      gas = 100

      # Base registers setup
      registers = %Registers{
        # machine ID
        r7: 1,
        # output address (second usable page)
        r8: 0x1_1000
      }

      {:ok, memory: memory, context: context, gas: gas, registers: registers}
    end

    test "returns panic when memory not readable at input", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory
    } do
      memory = Memory.set_access(memory, registers.r8, 1, nil)

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
      registers = %{registers | r7: 999}
      who = who()
      w8 = registers.r8

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^who, r8: ^w8},
               memory: ^memory,
               context: ^context
             } = Refine.invoke(gas, registers, memory, context)
    end

    test "executes program successfully", %{
      context: context,
      memory: memory,
      gas: gas,
      registers: registers
    } do
      halt = halt()
      registers = %{registers | r7: 2}

      registers_for_inner_execution =
        for x <- [42, 17, 83, 95, 29, 64, 71, 38, 56, 92, 13, 77],
            into: <<>>,
            do: <<x::64-little>>

      memory = Memory.write!(memory, registers.r8 + 8, registers_for_inner_execution)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^halt},
               memory: memory_,
               context: context_
             } = Refine.invoke(gas, registers, memory, context)

      # Read the execution results from memory
      {:ok, _gas_bytes} = Memory.read(memory_, registers.r8, 8)

      # Verify machine state in context
      machine = Map.get(context_.m, 2)
      # Should be at position 0 after halt
      assert machine.counter == 0

      assert {:ok, ^registers_for_inner_execution} =
               Memory.read(memory_, registers.r8 + 8, 12 * 8)
    end


    @tag :skip
    # TODO, rely on simpler program, this is too much to maintain
    test "executes program that panics", %{
      context: context,
      memory: memory,
      gas: gas,
      registers: registers
    } do
      panic = panic()
      w8 = registers.r8

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^panic, r8: ^w8},
               memory: memory_,
               context: context_
             } = Refine.invoke(gas, registers, memory, context)

      assert Memory.read!(memory_, registers.r8 + 16, 24) ==
               <<30::64-little, 11::64-little, 10::64-little>>

      machine = Map.get(context_.m, 1)
      assert Memory.read!(machine.memory, 0x10003, 4) == <<30::32-little>>
    end
  end
end
