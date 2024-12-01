defmodule PVM.Host.Refine.Internal.ExportTest do
  use ExUnit.Case
  alias PVM.Host.Refine.Internal
  alias PVM.{Memory, RefineContext}
  import PVM.Constants.HostCallResult

  describe "export_pure/4" do
    setup do
      memory = %Memory{}
      context = %RefineContext{e: []}  # Start with empty export list
      registers = List.duplicate(0, 13)
      export_offset = 0

      {:ok,
       memory: memory,
       context: context,
       registers: registers,
       export_offset: export_offset}
    end

    test "returns OOB when memory read fails", %{
      memory: memory,
      context: context,
      registers: registers,
      export_offset: export_offset
    } do
      registers =
        registers
        |> List.replace_at(7, 100)  # memory offset
        |> List.replace_at(8, 32)   # size

      # Make memory unreadable
      memory = Memory.set_access(memory, 100, 32, nil)

      {new_registers, new_memory, new_context} =
        Internal.export_pure(registers, memory, context, export_offset)

      assert new_registers == List.replace_at(registers, 7, oob())
      assert new_memory == memory
      assert new_context == context
    end

    test "returns FULL when manifest size limit would be exceeded", %{
      memory: memory,
      context: context,
      registers: registers,
      export_offset: export_offset
    } do
      # Fill context with max_manifest_size - 1 segments
      max_size = Constants.max_manifest_size()
      context = %{context | e: List.duplicate("", max_size + 1)}

      registers =
        registers
        |> List.replace_at(7, 0)   # memory offset
        |> List.replace_at(8, 32)  # size

      # Write some valid data to memory
      {:ok, memory} = Memory.write(memory, 0, String.duplicate("a", 32))

      {new_registers, new_memory, new_context} =
        Internal.export_pure(registers, memory, context, export_offset)

      assert new_registers == List.replace_at(registers, 7, full())
      assert new_memory == memory
      assert new_context == context
    end

    test "successful export with valid parameters", %{
      memory: memory,
      context: context,
      registers: registers,
      export_offset: export_offset
    } do
      test_data = "test_segment"
      {:ok, memory} = Memory.write(memory, 0, test_data)

      registers =
        registers
        |> List.replace_at(7, 0)    # memory offset
        |> List.replace_at(8, byte_size(test_data))  # size

      {new_registers, new_memory, new_context} =
        Internal.export_pure(registers, memory, context, export_offset)

      # Should return current export list length
      assert new_registers == List.replace_at(registers, 7, length(context.e) + export_offset)

      # Memory should be unchanged
      assert new_memory == memory

      # Context should have new segment added
      assert length(new_context.e) == length(context.e) + 1
      # Verify the exported segment is padded correctly
      assert List.last(new_context.e) == Utils.pad_binary_right(test_data, Constants.wswe())
    end
  end
end
