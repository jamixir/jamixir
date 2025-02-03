defmodule PVM.Host.Refine.ExportTest do
  use ExUnit.Case
  alias PVM.Host
  alias PVM.{Memory, Host.Refine.Context, Registers, Host.Refine.Result}
  import PVM.Constants.HostCallResult

  describe "export/5" do
    setup do
      memory = %Memory{}
      export_offset = 0
      gas = 100

      {:ok, memory: memory, export_offset: export_offset, gas: gas}
    end

    test "returns OOB when memory read fails", %{
      memory: memory,
      export_offset: export_offset,
      gas: gas
    } do
      registers = %Registers{r7: 100, r8: 32}

      # Make memory unreadable
      memory = Memory.set_access(memory, 100, 32, nil)

      %Result{registers: registers_, memory: memory_, context: context_} =
        Host.Refine.export(gas, registers, memory, %Context{}, export_offset)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == memory
      assert context_ == %Context{}
    end

    test "returns FULL when manifest size limit would be exceeded", %{
      memory: memory,
      export_offset: export_offset,
      gas: gas
    } do
      # Fill context with max_manifest_size - 1 segments
      max_size = Constants.max_manifest_size()
      context = %Context{e: List.duplicate("", max_size + 1)}

      registers = %Registers{r7: 0, r8: 32}

      # Write some valid data to memory
      {:ok, memory} = Memory.write(memory, 0, String.duplicate("a", 32))

      %Result{registers: registers_, memory: memory_, context: context_} =
        Host.Refine.export(gas, registers, memory, context, export_offset)

      assert registers_ == Registers.set(registers, 7, full())
      assert memory_ == memory
      assert context_ == context
    end

    test "successful export with valid parameters", %{
      memory: memory,
      export_offset: export_offset,
      gas: gas
    } do
      test_data = "test_segment"
      {:ok, memory} = Memory.write(memory, 0, test_data)

      registers = %Registers{r7: 0, r8: byte_size(test_data)}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Host.Refine.export(gas, registers, memory, %Context{}, export_offset)

      # Should return current export list length
      assert registers_ == Registers.set(registers, 7, export_offset)

      # Memory should be unchanged
      assert memory_ == memory

      # Context should have new segment added
      assert length(context_.e) == 1
      # Verify the exported segment is padded correctly
      assert List.last(context_.e) == Utils.pad_binary_right(test_data, Constants.segment_size())
    end
  end
end
