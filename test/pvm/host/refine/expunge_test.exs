defmodule PVM.Host.Refine.ExpungeTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Host.Refine.Context, Host.Refine.Result, Integrated, Registers}
  import PVM.Constants.HostCallResult
  import Pvm.Native

  describe "expunge/4" do
    setup do
      machine = %Integrated{program: "program", counter: 42}
      context = %Context{m: %{1 => machine}}
      gas = 100
      {:ok, context: context, machine: machine, gas: gas}
    end

    test "returns WHO when machine doesn't exist", %{context: context, gas: gas} do
      registers = Registers.new(%{7 => 999})

      %Result{registers: registers_, context: context_} =
        Refine.expunge(gas, registers, build_memory(), context)

      assert registers_ == Registers.new(%{7 => who()})
      assert context_ == context
    end

    test "successful expunge with valid machine ID", %{
      context: context,
      machine: machine,
      gas: gas
    } do
      registers = Registers.new(%{7 => 1})
      # add another machine to the context
      machine2 = %Integrated{program: "program2"}
      context = %{context | m: Map.put(context.m, 2, machine2)}

      %Result{registers: registers_, context: context_} =
        Refine.expunge(gas, registers, build_memory(), context)

      # Should return the machine's counter value
      assert registers_ == Registers.new(%{7 => machine.counter})

      # Machine should be removed from context
      assert context_ == %{context | m: %{2 => machine2}}
    end
  end
end
