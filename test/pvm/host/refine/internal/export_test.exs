defmodule PVM.Host.Refine.Internal.ExportTest do
  use ExUnit.Case
  alias PVM.Host.Refine.Internal
  alias PVM.{Memory, Refine, Registers}
  import PVM.Constants.HostCallResult

  describe "export_pure/4" do
    setup do
      memory = %Memory{}
      export_offset = 0

      {:ok,
       memory: memory,
       export_offset: export_offset}
    end

    test "returns OOB when memory read fails", %{
      memory: memory,
      export_offset: export_offset
    } do
      registers = %Registers{r7: 100, r8: 32}


      # Make memory unreadable
      memory = Memory.set_access(memory, 100, 32, nil)

      {new_registers, new_memory, new_context} =
        Internal.export_pure(registers, memory, %Refine.Context{}, export_offset)

      assert new_registers == Registers.set(registers, 7, oob())
      assert new_memory == memory
      assert new_context == %Refine.Context{}
    end

    test "returns FULL when manifest size limit would be exceeded", %{
      memory: memory,
      export_offset: export_offset
    } do
      # Fill context with max_manifest_size - 1 segments
      max_size = Constants.max_manifest_size()
      context = %Refine.Context{e: List.duplicate("", max_size + 1)}

      registers = %Registers{r7: 0, r8: 32}

      # Write some valid data to memory
      {:ok, memory} = Memory.write(memory, 0, String.duplicate("a", 32))

      {new_registers, new_memory, new_context} =
        Internal.export_pure(registers, memory, context, export_offset)

      assert new_registers == Registers.set(registers, 7, full())
      assert new_memory == memory
      assert new_context == context
    end

    test "successful export with valid parameters", %{
      memory: memory,
      export_offset: export_offset
    } do
      test_data = "test_segment"
      {:ok, memory} = Memory.write(memory, 0, test_data)

      registers = %Registers{r7: 0, r8: byte_size(test_data)}

      {new_registers, new_memory, new_context} =
        Internal.export_pure(registers, memory, %Refine.Context{}, export_offset)

      # Should return current export list length
      assert new_registers == Registers.set(registers, 7, export_offset)

      # Memory should be unchanged
      assert new_memory == memory

      # Context should have new segment added
      assert length(new_context.e) ==  1
      # Verify the exported segment is padded correctly
      assert List.last(new_context.e) == Utils.pad_binary_right(test_data, Constants.wswe())
    end
  end
end
