defmodule PVM.Host.Refine.Internal.VoidTest do
  use ExUnit.Case
  alias PVM.Host.Refine.Internal
  alias PVM.{Memory, RefineContext, Integrated, Registers}
  import PVM.Constants.HostCallResult

  describe "void_pure/3" do
    setup do
      {:ok, machine_memory} = Memory.write(%Memory{}, 0, "test_data")

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
      registers = %Registers{r7: 999, r8: 0, r9: 1}

      {new_registers, new_memory, new_context} =
        Internal.void_pure(registers, %Memory{}, context)

      assert new_registers.r7 == who()
      assert new_memory == %Memory{}
      assert new_context == context
    end

    test "returns OOB when page range is too large", %{
      context: context,
      machine: machine
    } do
      registers = %Registers{r7: 1, r8: 0, r9: trunc(:math.pow(2, 32))}

      {new_registers, new_memory, new_context} =
        Internal.void_pure(registers, %Memory{}, context)

      assert new_registers.r7 == oob()
      assert new_memory == %Memory{}
      assert new_context == context
    end

    test "returns OOB when page has empty access", %{
      context: context,
      machine: machine
    } do
      # Set empty access permission for target page
      machine = %{machine | memory: Memory.set_access_by_page(machine.memory, 1, 1, nil)}
      context = %{context | m: %{1 => machine}}

      registers = %Registers{r7: 1, r8: 1, r9: 1}

      {new_registers, new_memory, new_context} =
        Internal.void_pure(registers, %Memory{}, context)

      assert new_registers.r7 == oob()
      assert new_memory == %Memory{}
      assert new_context == context
    end

    test "successful void with valid parameters", %{
      context: context,
      machine: machine
    } do
      registers = %Registers{r7: 1, r8: 0, r9: 1}


      {new_registers, new_memory, new_context} =
        Internal.void_pure(registers, %Memory{}, context)

      assert new_registers.r7 == ok()
      assert new_memory == %Memory{}

      # Get updated machine
      machine = Map.get(new_context.m, 1)



      # Verify access permissions are empty
      refute Memory.check_pages_access?(machine.memory, 0, 1, :read)
      assert Memory.check_pages_access?(machine.memory, 1, 1, :write)

    end
  end
end
