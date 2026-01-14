defmodule PVM.Host.Refine.PagesTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Host.Refine.Context, Integrated, Registers}
  import PVM.Constants.HostCallResult
  import PVM.Memory.Constants
  import Pvm.Native

  @page_size PVM.Memory.Constants.page_size()

  defp a_0, do: min_allowed_address()

  describe "pages/4" do
    setup do
      test_data = String.duplicate("A", 256)

      machine_memory_ref = build_memory()
      set_memory_access(machine_memory_ref, a_0(), @page_size + 2, 3)
      memory_write(machine_memory_ref, a_0(), test_data)

      machine = %Integrated{
        memory: machine_memory_ref,
        program: "program"
      }

      context = %Context{m: %{1 => machine}}
      gas = 100

      # r7: machine ID, r8: start page, r9: page count
      registers =
        Registers.new(%{7 => 1, 8 => 16, 9 => 2})

      memory_ref = build_memory()

      {:ok,
       context: context,
       machine: machine,
       gas: gas,
       registers: registers,
       test_data: test_data,
       memory_ref: memory_ref}
    end

    test "returns WHO when machine doesn't exist", %{
      gas: gas,
      registers: registers,
      context: context,
      memory_ref: memory_ref
    } do
      who = who()
      registers = %{registers | r: put_elem(registers.r, 7, 99)}

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Refine.pages(gas, registers, memory_ref, context)

      assert registers_[7] == who
    end

    test "returns HUH when page number is too small", %{
      context: context,
      gas: gas,
      registers: registers,
      memory_ref: memory_ref
    } do
      # Set start page below minimum (16)
      registers = %{registers | r: put_elem(registers.r, 8, 15)}
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Refine.pages(gas, registers, memory_ref, context)

      assert registers_[7] == huh
    end

    test "returns HUH when page range is too large", %{
      context: context,
      gas: gas,
      registers: registers,
      memory_ref: memory_ref
    } do
      # Set page count to exceed 2^32/page_size
      registers = %{registers | r: put_elem(registers.r, 8, 0x1_FFFE) |> put_elem(9, 4)}
      huh = huh()

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Refine.pages(gas, registers, memory_ref, context)

      assert registers_[7] == huh
    end

    test "returns HUH when w10 > 4", %{
      context: context,
      gas: gas,
      registers: registers,
      memory_ref: memory_ref
    } do
      huh = huh()
      registers = %{registers | r: put_elem(registers.r, 10, 5)}

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Refine.pages(gas, registers, memory_ref, context)

      assert registers_[7] == huh
    end
  end

  describe "w10 is 3 or 4 and memory between w8 -> w8 + w9 has one or more nil access pages" do
    setup do
      registers =
        Registers.new(%{
          7 => 1,
          8 => 16,
          9 => 100
        })

      # Create a machine with memory that has nil access in the target range
      # read access for pages 16...+99, the 100th page will have nil access
      machine_memory_ref = build_memory()
      set_memory_access(machine_memory_ref, 16 * @page_size, 98 * @page_size + 1, 1)

      machine = %Integrated{
        memory: machine_memory_ref,
        program: "program"
      }

      context = %Context{m: %{1 => machine}}
      memory_ref = build_memory()

      {:ok, context: context, gas: 100, registers: registers, memory_ref: memory_ref}
    end

    test "returns HUH when w10 = 3 and memory has nil access pages", %{
      context: context,
      gas: gas,
      registers: registers,
      memory_ref: memory_ref
    } do
      registers = %{registers | r: put_elem(registers.r, 10, 3)}
      huh = huh()

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Refine.pages(gas, registers, memory_ref, context)

      assert registers_[7] == huh
    end

    test "returns HUH when w10 = 4 and memory has nil access pages", %{
      context: context,
      gas: gas,
      registers: registers,
      memory_ref: memory_ref
    } do
      registers = %{registers | r: put_elem(registers.r, 10, 4)}
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Refine.pages(gas, registers, memory_ref, context)

      assert registers_[7] == huh
    end
  end

  describe "success cases" do
    setup do
      test_data = String.duplicate("A", 256)

      # Page 16 starts at 16 * 4096 = 65536
      start_offset = 16 * @page_size

      machine_memory_ref = build_memory()
      # Set write access first to allow writing test data
      set_memory_access(machine_memory_ref, start_offset, 2 * @page_size, 3)
      # Write test data at the correct offset
      memory_write(machine_memory_ref, start_offset, test_data)
      # Then set read access for pages 16-17 (for modes 3/4 tests that require read access)
      set_memory_access(machine_memory_ref, start_offset, 2 * @page_size, 1)

      machine = %Integrated{
        memory: machine_memory_ref,
        program: "program"
      }

      context = %Context{m: %{1 => machine}}
      gas = 100

      # r7: machine ID, r8: start page, r9: page count
      registers =
        Registers.new(%{
          7 => 1,
          8 => 16,
          9 => 2
        })

      memory_ref = build_memory()

      {:ok,
       context: context,
       machine: machine,
       gas: gas,
       registers: registers,
       test_data: test_data,
       memory_ref: memory_ref}
    end

    test "r10 = 0 (zeroes and nil access pages)", %{
      context: context,
      gas: gas,
      registers: registers,
      memory_ref: memory_ref
    } do
      registers = %{registers | r: put_elem(registers.r, 10, 0)}
      ok = ok()

      assert %{exit_reason: :continue, registers: registers_, context: context_} =
               Refine.pages(gas, registers, memory_ref, context)

      assert registers_[7] == ok

      # Get updated machine
      machine = Map.get(context_.m, 1)

      # Calculate range
      start_offset = registers[8] * @page_size
      length = registers[9] * @page_size

      # Verify pages have nil access (read should fail)
      assert {:error, _} = memory_read(machine.memory, start_offset, length)
    end

    test "r10 = 1 (zeroes and read access pages)", %{
      context: context,
      gas: gas,
      registers: registers,
      memory_ref: memory_ref
    } do
      registers = %{registers | r: put_elem(registers.r, 10, 1)}
      ok = ok()

      assert %{exit_reason: :continue, registers: registers_, context: context_} =
               Refine.pages(gas, registers, memory_ref, context)

      assert registers_[7] == ok

      # Get updated machine
      machine = Map.get(context_.m, 1)

      # Calculate range
      start_offset = registers[8] * @page_size
      length = registers[9] * @page_size

      # Verify pages are zeroed
      {:ok, zeroed_data} = memory_read(machine.memory, start_offset, length)
      assert zeroed_data == <<0::size(length * 8)>>

      # Verify pages have read access but not write access
      # Write should fail for read-only memory
      assert {:error, _} = memory_write(machine.memory, start_offset, <<1>>)
    end

    test "r10 = 2 (zeroes and write access pages)", %{
      context: context,
      gas: gas,
      registers: registers,
      memory_ref: memory_ref
    } do
      registers = %{registers | r: put_elem(registers.r, 10, 2)}
      ok = ok()

      assert %{exit_reason: :continue, registers: registers_, context: context_} =
               Refine.pages(gas, registers, memory_ref, context)

      assert registers_[7] == ok

      # Get updated machine
      machine = Map.get(context_.m, 1)

      # Calculate range
      start_offset = registers[8] * @page_size
      length = registers[9] * @page_size

      # Verify pages are zeroed
      {:ok, zeroed_data} = memory_read(machine.memory, start_offset, length)
      assert zeroed_data == <<0::size(length * 8)>>

      # Verify pages have write access
      assert {:ok, _} = memory_write(machine.memory, start_offset, <<1>>)
    end

    test "r10 = 3 (memory values did not change, read access pages)", %{
      context: context,
      gas: gas,
      registers: registers,
      memory_ref: memory_ref,
      test_data: test_data
    } do
      registers = %{registers | r: put_elem(registers.r, 10, 3)}
      ok = ok()

      assert %{exit_reason: :continue, registers: registers_, context: context_} =
               Refine.pages(gas, registers, memory_ref, context)

      assert registers_[7] == ok

      # Get updated machine
      machine = Map.get(context_.m, 1)

      # Calculate range
      start_offset = registers[8] * @page_size
      length = byte_size(test_data)

      # Verify pages still contain original data (not zeroed)
      {:ok, unchanged_data} = memory_read(machine.memory, start_offset, length)
      assert unchanged_data == test_data

      # Verify pages have read access but not write access
      assert {:error, _} = memory_write(machine.memory, start_offset, <<1>>)
    end

    test "r10 = 4 (memory values did not change, write access pages)", %{
      gas: gas,
      registers: registers,
      memory_ref: memory_ref,
      test_data: test_data,
      context: context
    } do
      registers = %{registers | r: put_elem(registers.r, 10, 4)}
      ok = ok()

      assert %{exit_reason: :continue, registers: registers_, context: context_} =
               Refine.pages(gas, registers, memory_ref, context)

      assert registers_[7] == ok

      # Get updated machine
      machine = Map.get(context_.m, 1)

      # Calculate range
      start_offset = registers[8] * @page_size
      length = byte_size(test_data)

      # Verify pages still contain original data (not zeroed)
      {:ok, unchanged_data} = memory_read(machine.memory, start_offset, length)
      assert unchanged_data == test_data

      # Verify pages have write access
      assert {:ok, _} = memory_write(machine.memory, start_offset, <<1>>)
    end
  end
end
