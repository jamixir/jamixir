defmodule PVM.Host.Refine.VoidTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Integrated, Registers, Host.Refine.Result}
  import PVM.Constants.HostCallResult

  describe "void_pure/3" do
    setup do
      {:ok, machine_memory} = Memory.write(%Memory{}, 0, "test_data")

      machine = %Integrated{
        memory: machine_memory,
        program: "program"
      }

      context = %Context{m: %{1 => machine}}
      gas = 100

      {:ok, context: context, machine: machine, gas: gas}
    end

    test "returns WHO when machine doesn't exist", %{context: context, gas: gas} do
      registers = %Registers{r7: 999, r8: 0, r9: 1}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.void(gas, registers, %Memory{}, context)

      assert registers_ == Registers.set(registers, 7, who())
      assert memory_ == %Memory{}
      assert context_ == context
    end

    test "returns OOB when page range is too large", %{context: context, gas: gas} do
      registers = %Registers{r7: 1, r8: 0, r9: trunc(:math.pow(2, 32))}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.void(gas, registers, %Memory{}, context)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == %Memory{}
      assert context_ == context
    end

    test "returns OOB when page has empty access", %{
      context: context,
      machine: machine,
      gas: gas
    } do
      # Set empty access permission for target page
      machine = %{machine | memory: Memory.set_access_by_page(machine.memory, 1, 1, nil)}
      context = %{context | m: %{1 => machine}}

      registers = %Registers{r7: 1, r8: 1, r9: 1}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.void(gas, registers, %Memory{}, context)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == %Memory{}
      assert context_ == context
    end

    test "successful void with valid parameters", %{
      context: context,
      gas: gas
    } do
      registers = %Registers{r7: 1, r8: 0, r9: 1}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.void(gas, registers, %Memory{}, context)

      assert registers_.r7 == ok()
      assert memory_ == %Memory{}

      # Get updated machine
      machine = Map.get(context_.m, 1)

      # Verify access permissions are empty
      refute Memory.check_pages_access?(machine.memory, 0, 1, :read)
      assert Memory.check_pages_access?(machine.memory, 1, 1, :write)
    end
  end
end
