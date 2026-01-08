defmodule PVM.Host.Refine.ExportTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Host.Refine.Context, Registers}
  import Pvm.Native
  import PVM.Memory.Constants
  import PVM.Constants.HostCallResult
  def a_0, do: 0x1_0000

  describe "export/5" do
    setup do
      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 1)

      export_offset = 0
      gas = 100

      registers = Registers.new(%{7 => a_0(), 8 => 32})

      {:ok, memory_ref: memory_ref, export_offset: export_offset, gas: gas, registers: registers}
    end

    test "returns {:panic, w7} when memory not readable", %{
      memory_ref: memory_ref,
      export_offset: export_offset,
      gas: gas,
      registers: registers
    } do
      set_memory_access(memory_ref, registers[7], registers[8], 0)

      assert %{exit_reason: :panic, registers: ^registers, context: %Context{}} =
               Refine.export(gas, registers, memory_ref, %Context{}, export_offset)
    end

    test "returns {:continue, full()} when manifest size limit would be exceeded",
         %{memory_ref: memory_ref, gas: gas, registers: registers} do
      # Fill context with max_manifest_size + 1 segments
      max_size = Constants.max_imports()
      context = %Context{e: List.duplicate("", max_size - 5)}
      full = full()

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Refine.export(gas, registers, memory_ref, context, 10)

      assert registers_[7] == full
    end

    test "successful export with valid parameters",
         %{memory_ref: memory_ref, export_offset: export_offset, gas: gas, registers: registers} do
      test_data = "test_segment"
      test_da_load = byte_size(test_data)

      set_memory_access(memory_ref, min_allowed_address(), byte_size(test_data), 3)
      memory_write(memory_ref, registers[7], test_data)
      set_memory_access(memory_ref, min_allowed_address(), byte_size(test_data), 1)

      registers = %{registers | r: put_elem(registers.r, 8, test_da_load)}
      context = %Context{e: [<<1>>, <<2>>, <<3>>, <<4>>, <<5>>]}

      expected_w7 = export_offset + length(context.e)

      assert %{exit_reason: :continue, registers: registers_, context: context_} =
               Refine.export(gas, registers, memory_ref, context, export_offset)

      # Context should have new segment added
      assert length(context_.e) == length(context.e) + 1
      # Verify the exported segment is padded correctly
      assert List.last(context_.e) == Utils.pad_binary_right(test_data, Constants.segment_size())
      assert registers_[7] == expected_w7
    end
  end
end
