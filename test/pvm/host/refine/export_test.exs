defmodule PVM.Host.Refine.ExportTest do
  use ExUnit.Case
  alias PVM.PreMemory
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Registers}

  def a_0, do: 0x1_0000
  import PVM.Constants.HostCallResult

  describe "export/5" do
    setup do
      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.set_access(a_0(), 32, :read)
        |> PreMemory.finalize()

      export_offset = 0
      gas = 100

      registers = %Registers{
        r7: a_0(),
        r8: 32
      }

      {:ok, memory: memory, export_offset: export_offset, gas: gas, registers: registers}
    end

    test "returns {:panic, w7} when memory not readable", %{
      memory: memory,
      export_offset: export_offset,
      gas: gas,
      registers: registers
    } do
      # Make memory unreadable at the location
      memory = Memory.set_access(memory, registers.r7, registers.r8, nil)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: %Context{}
             } = Refine.export(gas, registers, memory, %Context{}, export_offset)
    end

    test "returns {:continue, full()} when manifest size limit would be exceeded", %{
      memory: memory,
      gas: gas,
      registers: registers
    } do
      # Fill context with max_manifest_size + 1 segments
      max_size = Constants.max_imports_and_exports()
      context = %Context{e: List.duplicate("", max_size - 5)}
      full = full()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^full},
               memory: ^memory,
               context: ^context
             } = Refine.export(gas, registers, memory, context, 10)
    end

    test "successful export with valid parameters", %{
      memory: memory,
      export_offset: export_offset,
      gas: gas,
      registers: registers
    } do
      test_data = "test_segment"
      test_da_load = byte_size(test_data)

      memory =
        Memory.set_access_by_page(memory, 16, 1, :write)
        |> Memory.write!(registers.r7, test_data)
        |> Memory.set_access_by_page(16, 1, :read)

      registers = %{registers | r8: test_da_load}
      context = %Context{e: [<<1>>, <<2>>, <<3>>, <<4>>, <<5>>]}

      expected_w7 = export_offset + length(context.e)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^expected_w7},
               memory: ^memory,
               context: context_
             } = Refine.export(gas, registers, memory, context, export_offset)

      # Context should have new segment added
      assert length(context_.e) == length(context.e) + 1
      # Verify the exported segment is padded correctly
      assert List.last(context_.e) == Utils.pad_binary_right(test_data, Constants.segment_size())
    end
  end
end
