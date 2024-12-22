defmodule PVM.Host.Refine.PokeTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Integrated, Registers, Host.Refine.Result}
  import PVM.Constants.HostCallResult

  describe "poke_pure/3" do
    setup do

      {:ok, machine_memory} = Memory.write(%Memory{}, 0, "initial_data")

      machine = %Integrated{
        memory: machine_memory,
        program: "program",
      }

      context = %Context{m: %{1 => machine}}
      gas = 100

      {:ok, context: context, machine: machine, gas: gas}
    end

    test "returns WHO when machine doesn't exist", %{
      context: context,
      gas: gas
    } do
      registers = %Registers{r7: 999, r8: 0, r9: 0, r10: 32}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.poke(gas, registers, %Memory{}, context)

      assert registers_ == Registers.set(registers, 7, who())
      assert memory_ == %Memory{}
      assert context_ == context
    end

    test "returns OOB when source memory read fails", %{
      context: context,
      gas: gas
    } do
      # Make source memory unreadable
      memory = Memory.set_access(%Memory{}, 0, 32, nil)

      registers = %Registers{r7: 1, r8: 0, r9: 0, r10: 32}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.poke(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == memory
      assert context_ == context
    end

    test "returns OOB when destination memory is not writable", %{
      context: context,
      machine: machine,
      gas: gas
    } do
      # Make destination memory unwritable in the machine
      machine = %{machine | memory: Memory.set_access(machine.memory, 0, 32, :read)}
      context = %{context | m: %{1 => machine}}

      test_data = "test_data"
      {:ok, memory} = Memory.write(%Memory{}, 100, test_data)

      registers = %Registers{r7: 1, r8: 100, r9: 0, r10: 32}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.poke(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == memory
      assert context_ == context
    end

    test "successful poke with valid parameters", %{
      context: context,
      gas: gas
    } do
      test_data = "test_data"
      {:ok, memory} = Memory.write(%Memory{}, 100, test_data)

      registers = %Registers{r7: 1, r8: 100, r9: 0, r10: 32}


      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.poke(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, ok())
      assert memory_ == memory

      # Verify data was written to machine memory
      machine = Map.get(context_.m, 1)
      {:ok, ^test_data} = Memory.read(machine.memory, 0, byte_size(test_data))
    end
  end
end
