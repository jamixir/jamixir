defmodule PVM.Host.Refine.Internal.ZeroTest do
  use ExUnit.Case
  alias PVM.Host.Refine.Internal
  alias PVM.{Memory, RefineContext, Integrated, Registers}
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


      {:ok,
       context: context,
       machine: machine}
    end

    test "returns WHO when machine doesn't exist", %{
      context: context,
      machine: machine
    } do
      registers = %Registers{r7: 999, r8: 16, r9: 1}

      {new_registers, new_memory, new_context} =
        Internal.zero_pure(registers, %Memory{}, context)

      assert new_registers.r7 == who()
      assert new_memory == %Memory{}
      assert new_context == context
    end

    test "returns OOB when page number is too small", %{
      context: context,
      machine: machine
    } do
      registers = %Registers{r7: 1, r8: 15, r9: 1}


      {new_registers, new_memory, new_context} =
        Internal.zero_pure(registers, %Memory{}, context)

      assert new_registers.r7 == oob()
      assert new_memory == %Memory{}
      assert new_context == context
    end

    test "returns OOB when page range is too large", %{
      context: context,
      machine: machine
    } do
      registers = %Registers{r7: 1, r8: 16, r9: trunc(:math.pow(2, 32) / 64)}

      {new_registers, new_memory, new_context} =
        Internal.zero_pure(registers, %Memory{}, context)

      assert new_registers.r7 == oob()
      assert new_memory == %Memory{}
      assert new_context == context
    end

    test "successful zero with valid parameters", %{
      context: context,
      machine: machine
    } do
      page = 16
      count = 2

      registers = %Registers{r7: 1, r8: page, r9: count}


      {new_registers, new_memory, new_context} =
        Internal.zero_pure(registers, %Memory{}, context)

      assert new_registers.r7 == ok()
      assert new_memory == %Memory{}

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
