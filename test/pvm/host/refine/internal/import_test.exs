defmodule PVM.Host.Refine.Internal.ImportTest do
  use ExUnit.Case
  alias PVM.Host.Refine.Internal
  alias PVM.{Memory, RefineContext}
  import PVM.Constants.HostCallResult

  describe "import_pure/4" do
    setup do
      memory = %Memory{}
      context = %RefineContext{}
      # Initialize 13 registers with zeros
      registers = List.duplicate(0, 13)
      import_segments = ["segment1", "segment2", "segment3"]

      {:ok,
       memory: memory,
       context: context,
       registers: registers,
       import_segments: import_segments}
    end

    test "returns OOB when memory is not writable", %{
      memory: memory,
      context: context,
      registers: registers,
      import_segments: import_segments
    } do
      registers =
        registers
        |> List.replace_at(7, 0)  # Valid segment index
        |> List.replace_at(8, 100)  # offset
        |> List.replace_at(9, 32)   # length

      # Make memory read-only
      memory = Memory.set_access(memory, 100, 32, :read)

      {new_registers, new_memory, new_context} =
        Internal.import_pure(registers, memory, context, import_segments)

      assert Enum.at(new_registers, 7) == oob()
      assert new_memory == memory
      assert new_context == context
    end

    test "returns NONE when segment index is out of bounds", %{
      memory: memory,
      context: context,
      registers: registers,
      import_segments: import_segments
    } do
      registers =
        registers
        |> List.replace_at(7, 999)  # Invalid segment index
        |> List.replace_at(8, 0)    # offset
        |> List.replace_at(9, 32)   # length

      {new_registers, new_memory, new_context} =
        Internal.import_pure(registers, memory, context, import_segments)

      assert Enum.at(new_registers, 7) == none()
      assert new_memory == memory
      assert new_context == context
    end

    test "successful import with valid parameters", %{
      memory: memory,
      context: context,
      registers: registers,
      import_segments: import_segments
    } do
      registers =
        registers
        |> List.replace_at(7, 0)    # First segment
        |> List.replace_at(8, 100)  # offset
        |> List.replace_at(9, 32)   # length

      {new_registers, new_memory, new_context} =
        Internal.import_pure(registers, memory, context, import_segments)

      assert Enum.at(new_registers, 7) == ok()

      # Verify the segment was written to memory
      {:ok, written_value} = Memory.read(new_memory, 100, String.length(Enum.at(import_segments, 0)))
      assert written_value == Enum.at(import_segments, 0)

      assert new_context == context
    end
  end
end 
