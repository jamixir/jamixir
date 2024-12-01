defmodule PVM.Host.Refine.Internal.PokeTest do
  use ExUnit.Case
  alias PVM.Host.Refine.Internal
  alias PVM.{Memory, RefineContext, Integrated}
  import PVM.Constants.HostCallResult

  describe "poke_pure/3" do
    setup do

      {:ok, machine_memory} = Memory.write(%Memory{}, 0, "initial_data")

      machine = %Integrated{
        memory: machine_memory,
        program: "program",
      }

      context = %RefineContext{m: %{1 => machine}}
      memory = %Memory{}
      registers = List.duplicate(0, 13)

      {:ok,
       memory: memory,
       context: context,
       registers: registers,
       machine: machine}
    end

    test "returns WHO when machine doesn't exist", %{
      memory: memory,
      context: context,
      registers: registers
    } do
      registers =
        registers
        |> List.replace_at(7, 999)  # non-existent machine ID
        |> List.replace_at(8, 0)    # source offset
        |> List.replace_at(9, 0)   # destination offset
        |> List.replace_at(10, 32)   # size

      {new_registers, new_memory, new_context} =
        Internal.poke_pure(registers, memory, context)

      assert Enum.at(new_registers, 7) == who()
      assert new_memory == memory
      assert new_context == context
    end

    test "returns OOB when source memory read fails", %{
      memory: memory,
      context: context,
      registers: registers
    } do
      # Make source memory unreadable
      memory = Memory.set_access(memory, 0, 32, nil)

      registers =
        registers
        |> List.replace_at(7, 1)    # existing machine ID
        |> List.replace_at(8, 0)    # source offset
        |> List.replace_at(9, 0)   # destination offset
        |> List.replace_at(10, 32)   # size

      {new_registers, new_memory, new_context} =
        Internal.poke_pure(registers, memory, context)

      assert Enum.at(new_registers, 7) == oob()
      assert new_memory == memory
      assert new_context == context
    end

    test "returns OOB when destination memory is not writable", %{
      memory: memory,
      context: context,
      registers: registers,
      machine: machine
    } do
      # Make destination memory unwritable in the machine
      machine = %{machine | memory: Memory.set_access(machine.memory, 0, 32, :read)}
      context = %{context | m: %{1 => machine}}

      test_data = "test_data"
      {:ok, memory} = Memory.write(memory, 100, test_data)

      registers =
        registers
        |> List.replace_at(7, 1)    # existing machine ID
        |> List.replace_at(8, 100)  # source offset
        |> List.replace_at(9, 0)   # destination offset
        |> List.replace_at(10, 32)   # size

      {new_registers, new_memory, new_context} =
        Internal.poke_pure(registers, memory, context)

      assert Enum.at(new_registers, 7) == oob()
      assert new_memory == memory
      assert new_context == context
    end

    test "successful poke with valid parameters", %{
      memory: memory,
      context: context,
      registers: registers
    } do
      test_data = "test_data"
      {:ok, memory} = Memory.write(memory, 100, test_data)

      registers =
        registers
        |> List.replace_at(7, 1)    # existing machine ID
        |> List.replace_at(8, 100)  # source offset
        |> List.replace_at(9, 0)   # destination offset
        |> List.replace_at(10, 32)   # size

      {new_registers, new_memory, new_context} =
        Internal.poke_pure(registers, memory, context)

      assert Enum.at(new_registers, 7) == ok()
      assert new_memory == memory

      # Verify data was written to machine memory
      machine = Map.get(new_context.m, 1)
      {:ok, ^test_data} = Memory.read(machine.memory, 0, byte_size(test_data))
    end
  end
end
