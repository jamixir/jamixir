defmodule PVM.Host.Refine.ImportTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Refine.Context, Registers}
  import PVM.Constants.HostCallResult

  describe "import/4" do
    setup do
      memory = %Memory{}
      import_segments = ["segment1", "segment2", "segment3"]
      gas = 100

      {:ok,
       memory: memory,
       import_segments: import_segments,
       gas: gas}
    end

    test "returns OOB when memory is not writable", %{
      memory: memory,
      import_segments: import_segments,
      gas: gas
    } do
      registers = %Registers{r7: 0, r8: 100, r9: 32}

      # Make memory read-only
      memory = Memory.set_access(memory, 100, 32, :read)

      {_exit_reason, %{registers: new_registers, memory: new_memory}, new_context} =
        Refine.import(gas, registers, memory, %Context{}, import_segments)

      assert new_registers.r7 == oob()
      assert new_memory == memory
      assert new_context == %Context{}
    end

    test "returns NONE when segment index is out of bounds", %{
      memory: memory,
      import_segments: import_segments,
      gas: gas
    } do
      registers = %Registers{r7: 999, r8: 0, r9: 32}

      {_exit_reason, %{registers: new_registers, memory: new_memory}, new_context} =
        Refine.import(gas, registers, memory, %Context{}, import_segments)

      assert new_registers.r7 == none()
      assert new_memory == memory
      assert new_context == %Context{}
    end

    test "successful import with valid parameters", %{
      memory: memory,
      import_segments: import_segments,
      gas: gas
    } do
      registers = %Registers{r7: 0, r8: 100, r9: 32}

      {_exit_reason, %{registers: new_registers, memory: new_memory}, new_context} =
        Refine.import(gas, registers, memory, %Context{}, import_segments)

      assert new_registers.r7 == ok()

      # Verify the segment was written to memory
      {:ok, written_value} = Memory.read(new_memory, 100, String.length(Enum.at(import_segments, 0)))
      assert written_value == Enum.at(import_segments, 0)

      assert new_context == %Context{}
    end
  end
end
