defmodule PVM.Host.Refine.ExpungeTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Refine.Context, Integrated, Registers}
  import PVM.Constants.HostCallResult

  describe "expunge/4" do
    setup do
      machine = %Integrated{
        memory: %Memory{},
        program: "program",
        counter: 42
      }

      context = %Context{m: %{1 => machine}}
      gas = 100

      {:ok, context: context, machine: machine, gas: gas}
    end

    test "returns WHO when machine doesn't exist", %{context: context, gas: gas} do
      registers = %Registers{r7: 999}

      {_exit_reason, %{registers: new_registers, memory: new_memory}, new_context} =
        Refine.expunge(gas, registers, %Memory{}, context)

      assert new_registers.r7 == who()
      assert new_memory == %Memory{}
      assert new_context == context
    end

    test "successful expunge with valid machine ID", %{context: context, machine: machine, gas: gas} do
      registers = %Registers{r7: 1}
      # add another machine to the context
      machine2 = %Integrated{program: "program2"}
      context = %{context | m: Map.put(context.m, 2, machine2)}

      {_exit_reason, %{registers: new_registers, memory: new_memory}, new_context} =
        Refine.expunge(gas, registers, %Memory{}, context)

      # Should return the machine's counter value
      assert new_registers.r7 == machine.counter
      assert new_memory == %Memory{}

      # Machine should be removed from context
      assert new_context.m == %{2 => machine2}
    end
  end
end
