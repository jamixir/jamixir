defmodule PVM.Host.Refine.Internal.InvokeTest do
  use ExUnit.Case
  alias PVM.Host.Refine.Internal
  alias PVM.{Memory, RefineContext, Integrated, Registers, State}
  import PVM.Constants.{HostCallResult, InnerPVMResult}
  use Codec.Decoder

  describe "invoke_pure/3" do
    setup do
      # Program that sets registers [1,2,3] to [30,11,10] and halts
      {:ok, program} =
        Base.decode16(
          "00012a33010033020133030a3305020156120a14af520452140008aa12010179220128ee3d0103320c0000ffff010000010000010000010000010100000001000001000000010000010100000100010000010000000000",
          case: :lower
        )

      machine = %Integrated{
        program: program
      }

      context = %RefineContext{m: %{1 => machine}}
      memory = %Memory{}

      {:ok, context: context, memory: memory, machine: machine}
    end

    test "returns OOB when memory is not readable", %{context: context} do
      registers = %Registers{r7: 1, r8: 0}
      memory = %Memory{} |> Memory.set_default_access(nil)

      {new_registers, new_memory, new_context} =
        Internal.invoke_pure(registers, memory, context)

      assert new_registers.r7 == oob()
      assert new_memory == memory
      assert new_context == context
    end

    test "returns WHO when machine doesn't exist", %{memory: memory, context: context} do
      registers = %Registers{r7: 999, r8: 0}

      {new_registers, new_memory, new_context} =
        Internal.invoke_pure(registers, memory, context)

      assert new_registers.r7 == who()
      assert new_memory == memory
      assert new_context == context
    end

    test "executes program successfully", %{context: context, memory: memory} do
      # Set up registers with machine ID (1) and output offset (0)
      registers = %Registers{r7: 1, r8: 0}

      {new_registers, new_memory, new_context} =
        Internal.invoke_pure(registers, memory, context)

      # Check that execution halted successfully
      assert new_registers.r7 == halt()

      # Read the execution results from memory
      {:ok, gas_bytes} = Memory.read(new_memory, 0, 8)
      {:ok, register_bytes} = Memory.read(new_memory, 8, 13 * 4)

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
      machine = Map.get(new_context.m, 1)
      # Should be at position 0 after halt
      assert machine.counter == 0
      assert {:ok, <<30>>} = Memory.read(machine.memory, 3, 1)
    end
  end
end
