defmodule PVM.Host.Refine.Internal.ZeroTest do
  use ExUnit.Case
  alias PVM.Host.Refine.Internal
  alias PVM.{Memory, RefineContext, Integrated}
  import PVM.Constants.HostCallResult

  describe "zero_pure/3" do
    setup do
      machine_memory = %Memory{}
      page_size = machine_memory.page_size
      # Write some test data to verify it gets zeroed
      {:ok, machine_memory} = Memory.write(machine_memory, 16 * page_size, "test_data")

      machine = %Integrated{
        memory: machine_memory,
        program: "program"
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
        |> List.replace_at(8, 16)   # page number
        |> List.replace_at(9, 1)    # page count

      {new_registers, new_memory, new_context} =
        Internal.zero_pure(registers, memory, context)

      assert Enum.at(new_registers, 7) == who()
      assert new_memory == memory
      assert new_context == context
    end

    test "returns OOB when page number is too small", %{
      memory: memory,
      context: context,
      registers: registers
    } do
      registers =
        registers
        |> List.replace_at(7, 1)    # existing machine ID
        |> List.replace_at(8, 15)   # page number < 16
        |> List.replace_at(9, 1)    # page count

      {new_registers, new_memory, new_context} =
        Internal.zero_pure(registers, memory, context)

      assert Enum.at(new_registers, 7) == oob()
      assert new_memory == memory
      assert new_context == context
    end

    test "returns OOB when page range is too large", %{
      memory: memory,
      context: context,
      registers: registers
    } do
      registers =
        registers
        |> List.replace_at(7, 1)    # existing machine ID
        |> List.replace_at(8, 16)   # page number
        |> List.replace_at(9, trunc(:math.pow(2, 32) / 64))  # too many pages

      {new_registers, new_memory, new_context} =
        Internal.zero_pure(registers, memory, context)

      assert Enum.at(new_registers, 7) == oob()
      assert new_memory == memory
      assert new_context == context
    end

    test "successful zero with valid parameters", %{
      memory: memory,
      context: context,
      registers: registers
    } do
      page = 16
      count = 2

      registers =
        registers
        |> List.replace_at(7, 1)    # existing machine ID
        |> List.replace_at(8, page) # page number
        |> List.replace_at(9, count)# page count

      {new_registers, new_memory, new_context} =
        Internal.zero_pure(registers, memory, context)

      assert Enum.at(new_registers, 7) == ok()
      assert new_memory == memory

      # Get updated machine
      %Integrated{memory: u_} = Map.get(new_context.m, 1)
      page_size = u_.page_size

      # Verify pages are zeroed
      start_offset = page * page_size
      length = count * page_size
      {:ok, zeroed_data} = Memory.read(u_, start_offset, length)
      assert zeroed_data == <<0::size(length * 8)>>

      # Verify pages are writable
      assert Memory.check_range_access?(u_, start_offset, length, :write)
    end
  end
end
