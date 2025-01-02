defmodule PVM.Host.Refine.ImportTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Registers, Host.Refine.Result}
  import PVM.Constants.HostCallResult

  describe "import/4" do
    setup do
      memory = %Memory{}
      import_segments = ["segment1", "segment2", "segment3"]
      gas = 100

      {:ok, memory: memory, import_segments: import_segments, gas: gas}
    end

    test "returns OOB when memory is not writable", %{
      memory: memory,
      import_segments: import_segments,
      gas: gas
    } do
      registers = %Registers{r7: 0, r8: 100, r9: 32}

      # Make memory read-only
      memory = Memory.set_access(memory, 100, 32, :read)

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.import(gas, registers, memory, %Context{}, import_segments)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == memory
      assert context_ == %Context{}
    end

    test "returns NONE when segment index is out of bounds", %{
      memory: memory,
      import_segments: import_segments,
      gas: gas
    } do
      registers = %Registers{r7: 999, r8: 0, r9: 32}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.import(gas, registers, memory, %Context{}, import_segments)

      assert registers_ == Registers.set(registers, 7, none())
      assert memory_ == memory
      assert context_ == %Context{}
    end

    test "successful import with valid parameters", %{
      memory: memory,
      import_segments: import_segments,
      gas: gas
    } do
      registers = %Registers{r7: 0, r8: 100, r9: 32}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Refine.import(gas, registers, memory, %Context{}, import_segments)

      assert registers_ == Registers.set(registers, 7, ok())

      # Verify the segment was written to memory
      {:ok, written_value} = Memory.read(memory_, 100, String.length(Enum.at(import_segments, 0)))
      assert written_value == Enum.at(import_segments, 0)

      assert context_ == %Context{}
    end
  end
end
