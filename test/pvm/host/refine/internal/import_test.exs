defmodule PVM.Host.Refine.Internal.ImportTest do
  use ExUnit.Case
  alias PVM.Host.Refine.Internal
  alias PVM.{Memory, Refine, Registers}
  import PVM.Constants.HostCallResult

  describe "import_pure/4" do
    setup do
      memory = %Memory{}
      import_segments = ["segment1", "segment2", "segment3"]

      {:ok,
       memory: memory,
       import_segments: import_segments}
    end

    test "returns OOB when memory is not writable", %{
      memory: memory,
      import_segments: import_segments
    } do
      registers = %Registers{r7: 0, r8: 100, r9: 32}

      # Make memory read-only
      memory = Memory.set_access(memory, 100, 32, :read)

      {new_registers, new_memory, new_context} =
        Internal.import_pure(registers, memory, %Refine.Context{}, import_segments)

      assert new_registers.r7 == oob()
      assert new_memory == memory
      assert new_context == %Refine.Context{}
    end

    test "returns NONE when segment index is out of bounds", %{
      memory: memory,
      import_segments: import_segments
    } do
      registers = %Registers{r7: 999, r8: 0, r9: 32}

      {new_registers, new_memory, new_context} =
        Internal.import_pure(registers, memory, %Refine.Context{}, import_segments)

      assert new_registers.r7 == none()
      assert new_memory == memory
      assert new_context == %Refine.Context{}
    end

    test "successful import with valid parameters", %{
      memory: memory,
      import_segments: import_segments
    } do
      registers = %Registers{r7: 0, r8: 100, r9: 32}

      {new_registers, new_memory, new_context} =
        Internal.import_pure(registers, memory, %Refine.Context{}, import_segments)

      assert new_registers.r7 == ok()

      # Verify the segment was written to memory
      {:ok, written_value} = Memory.read(new_memory, 100, String.length(Enum.at(import_segments, 0)))
      assert written_value == Enum.at(import_segments, 0)

      assert new_context == %Refine.Context{}
    end
  end
end
