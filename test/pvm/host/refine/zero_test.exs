defmodule PVM.Host.Refine.ZeroTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Integrated, Registers, Host.Refine.Result}
  import PVM.Constants.HostCallResult

  describe "zero/4" do
    setup do
      machine_memory = %Memory{}
      page_size = machine_memory.page_size
      # Write some test data to verify it gets zeroed
      {:ok, machine_memory} = Memory.write(machine_memory, 16 * page_size, "test_data")

      machine = %Integrated{
        memory: machine_memory,
        program: "program"
      }

      context = %Context{m: %{1 => machine}}
      gas = 100

      {:ok, context: context, machine: machine, gas: gas}
    end

    test "returns WHO when machine doesn't exist", %{context: context, gas: gas} do
      registers = %Registers{r7: 999, r8: 16, r9: 1}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.zero(gas, registers, %Memory{}, context)

      assert registers_ == Registers.set(registers, 7, who())
      assert memory_ == %Memory{}
      assert context_ == context
    end

    test "returns OOB when page number is too small", %{context: context, gas: gas} do
      registers = %Registers{r7: 1, r8: 15, r9: 1}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.zero(gas, registers, %Memory{}, context)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == %Memory{}
      assert context_ == context
    end

    test "returns OOB when page range is too large", %{context: context, gas: gas} do
      registers = %Registers{r7: 1, r8: 16, r9: trunc(:math.pow(2, 32) / 64)}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.zero(gas, registers, %Memory{}, context)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == %Memory{}
      assert context_ == context
    end

    test "successful zero with valid parameters", %{context: context, gas: gas} do
      page = 16
      count = 2

      registers = %Registers{r7: 1, r8: page, r9: count}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.zero(gas, registers, %Memory{}, context)

      assert registers_ == Registers.set(registers, 7, ok())
      assert memory_ == %Memory{}

      # Get updated machine
      %Integrated{memory: u_} = Map.get(context_.m, 1)
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
