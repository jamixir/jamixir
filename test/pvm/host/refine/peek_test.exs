defmodule PVM.Host.Refine.PeekTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Integrated, Registers, Host.Refine.Result}
  import PVM.Constants.HostCallResult

  describe "peek_pure/3" do
    setup do
      {:ok, source_memory} = Memory.write(%Memory{}, 0, "test_data")

      machine = %Integrated{
        memory: source_memory,
        program: "program"
      }

      context = %Context{m: %{1 => machine}}
      gas = 100

      {:ok, context: context, machine: machine, gas: gas}
    end

    test "returns WHO when machine doesn't exist", %{context: context, gas: gas} do
      registers = %Registers{r7: 999, r8: 0, r9: 32, r10: 100}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.peek(gas, registers, %Memory{}, context)

      assert registers_ == Registers.set(registers, 7, who())
      assert memory_ == %Memory{}
      assert context_ == context
    end

    test "returns OOB when source memory read fails", %{
      context: context,
      machine: machine,
      gas: gas
    } do
      # Make source memory unreadable
      machine = %{machine | memory: Memory.set_access(machine.memory, 0, 32, nil)}
      context = %{context | m: %{1 => machine}}

      registers = %Registers{r7: 1, r8: 0, r9: 32, r10: 100}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.peek(gas, registers, %Memory{}, context)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == %Memory{}
      assert context_ == context
    end

    test "returns OOB when destination memory write fails", %{
      context: context,
      gas: gas
    } do
      # Make destination memory unwritable
      memory = Memory.set_access(%Memory{}, 100, 32, :read)

      registers = %Registers{r7: 1, r8: 0, r9: 32, r10: 100}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.peek(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == memory
      assert context_ == context
    end

    test "successful peek with valid parameters", %{
      context: context,
      machine: machine,
      gas: gas
    } do
      test_data = "test_data"

      registers = %Registers{r7: 1, r8: 100, r9: 0, r10: byte_size(test_data)}

      machine = %{machine | memory: Memory.write(machine.memory, 0, test_data) |> elem(1)}
      context = %{context | m: %{1 => machine}}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.peek(gas, registers, %Memory{}, context)

      assert registers_ == Registers.set(registers, 7, ok())

      # Verify data was copied correctly
      {:ok, ^test_data} = Memory.read(memory_, 100, byte_size(test_data))

      assert context_ == context
    end
  end
end
