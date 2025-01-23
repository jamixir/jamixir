defmodule PVM.Host.Refine.InvokeTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Integrated, Registers, Host.Refine.Result}
  import PVM.Constants.{HostCallResult, InnerPVMResult}
  use Codec.Decoder
  import Util.Hex

  describe "invoke/4" do
    setup do
      # Program that sets registers [1,2,3] to [30,11,10] and halts
      program =
        decode16!(
          "00012a33010033020133030a3305020156120a14af520452140008aa12010179220128ee3d0103320c0000ffff010000010000010000010000010100000001000001000000010000010100000100010000010000000000"
        )

      machine = %Integrated{
        program: program
      }

      context = %Context{m: %{1 => machine}}
      memory = %Memory{}
      gas = 100

      {:ok, context: context, memory: memory, machine: machine, gas: gas}
    end

    test "returns OOB when memory is not readable", %{context: context, gas: gas} do
      registers = %Registers{r7: 1, r8: 0}
      memory = %Memory{} |> Memory.set_default_access(nil)

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.invoke(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == memory
      assert context_ == context
    end

    test "returns WHO when machine doesn't exist", %{memory: memory, context: context, gas: gas} do
      registers = %Registers{r7: 999, r8: 0}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.invoke(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, who())
      assert memory_ == memory
      assert context_ == context
    end

    test "executes program successfully", %{context: context, memory: memory, gas: gas} do
      # Set up registers with machine ID (1) and output offset (0)
      registers = %Registers{r7: 1, r8: 0}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.invoke(gas, registers, memory, context)

      # Check that execution halted successfully
      assert registers_ == Registers.set(registers, 7, halt())

      # Read the execution results from memory
      {:ok, _gas_bytes} = Memory.read(memory_, 0, 8)
      {:ok, register_bytes} = Memory.read(memory_, 8, 13 * 4)

      # Decode registers from memory
      internal_vm_registers =
        register_bytes
        |> :binary.bin_to_list()
        |> Enum.chunk_every(4)
        |> Enum.map(&:binary.list_to_bin/1)
        |> Enum.map(&de_le(&1, 4))
        |> Enum.with_index()
        |> Enum.into(%{}, fn {value, index} ->
          {:"r#{index}", value}
        end)
        |> then(&struct(Registers, &1))

      # Check that registers [1,2,3] contain [30,11,10]
      assert Registers.get(internal_vm_registers, [1, 2, 3]) == [30, 11, 10]

      # Verify machine state in context
      machine = Map.get(context_.m, 1)
      # Should be at position 0 after halt
      assert machine.counter == 0
      assert {:ok, <<30>>} = Memory.read(machine.memory, 3, 1)
    end
  end
end
