defmodule PVM.Host.Refine.ExpungeTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Integrated, Registers, Host.Refine.Result}
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
      registers = Registers.new(%{7 => 999})

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.expunge(gas, registers, %Memory{}, context)

      assert registers_ == Registers.new(%{7 => who()})
      assert memory_ == %Memory{}
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

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.expunge(gas, registers, %Memory{}, context)

      # Should return the machine's counter value
      assert registers_ == Registers.new(%{7 => machine.counter})
      assert memory_ == %Memory{}

      # Machine should be removed from context
      assert context_ == %{context | m: %{2 => machine2}}
    end
  end
end
