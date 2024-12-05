defmodule PVM.Host.Refine.Internal.ExpungeTest do
  use ExUnit.Case
  alias PVM.Host.Refine.Internal
  alias PVM.{Memory, RefineContext, Integrated, Registers}
  import PVM.Constants.HostCallResult

  describe "expunge_pure/3" do
    setup do
      machine = %Integrated{
        memory: %Memory{},
        program: "program",
        counter: 42
      }

      context = %RefineContext{m: %{1 => machine}}

      {:ok, context: context, machine: machine}
    end

    test "returns WHO when machine doesn't exist", %{context: context} do
      registers = %Registers{r7: 999}

      {new_registers, new_memory, new_context} =
        Internal.expunge_pure(registers, %Memory{}, context)

      assert new_registers.r7 == who()
      assert new_memory == %Memory{}
      assert new_context == context
    end

    test "successful expunge with valid machine ID", %{context: context, machine: machine} do
      registers = %Registers{r7: 1}
      # add another machine to the context
      machine2 = %Integrated{program: "program2"}
      context = %{context | m: Map.put(context.m, 2, machine2)}

      {new_registers, new_memory, new_context} =
        Internal.expunge_pure(registers, %Memory{}, context)

      # Should return the machine's counter value
      assert new_registers.r7 == machine.counter
      assert new_memory == %Memory{}

      # Machine should be removed from context
      assert new_context.m == %{2 => machine2}
    end
  end
end
