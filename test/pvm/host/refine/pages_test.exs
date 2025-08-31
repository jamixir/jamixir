defmodule PVM.Host.Refine.PagesTest do
  use ExUnit.Case
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Integrated, Registers, PreMemory}
  import PVM.Constants.HostCallResult
  import PVM.Memory.Constants

  describe "pages/4" do
    setup do
      test_data = String.duplicate("A", 256)

      machine_memory =
        PreMemory.init_nil_memory()
        |> PreMemory.set_access(min_allowed_address(), page_size() + 2, :write)
        |> PreMemory.write(min_allowed_address(), test_data)
        |> PreMemory.finalize()

      machine = %Integrated{
        memory: machine_memory,
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

      memory = PreMemory.init_nil_memory() |> PreMemory.finalize()

      {:ok,
       context: context,
       machine: machine,
       gas: gas,
       registers: registers,
       test_data: test_data,
       memory: memory,
       test_data: test_data}
    end

    test "returns WHO when machine doesn't exist", %{
      gas: gas,
      registers: registers,
      context: context,
      memory: memory
    } do
      who = who()
      registers = %{registers | r: put_elem(registers.r, 7, 99)}

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: ^context
             } = Refine.pages(gas, registers, memory, context)

      assert registers_[7] == who
    end

    test "returns HUH when page number is too small", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory
    } do
      # Set start page below minimum (16)
      registers = %{registers | r: put_elem(registers.r, 8, 15)}
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: ^context
             } = Refine.pages(gas, registers, memory, context)

      assert registers_[7] == huh
    end

    test "returns HUH when page range is too large", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory
    } do
      # Set page count to exceed 2^32/page_size
      registers = %{registers | r: put_elem(registers.r, 8, 0x1_FFFE) |> put_elem(9, 4)}
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: ^context
             } = Refine.pages(gas, registers, memory, context)

      assert registers_[7] == huh
    end

    test "returns HUH when w10 > 4", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory
    } do
      huh = huh()
      registers = %{registers | r: put_elem(registers.r, 10, 5)}

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: ^context
             } = Refine.pages(gas, registers, memory, context)

      assert registers_[7] == huh
    end
  end

  describe "w10 is 3 or 4 and memory between w8 -> w8 + w9 has one or more nil access pages" do
    setup do
      registers = Registers.new(%{
        7 => 1,
        8 => 16,
        9 => 100
      })

      # Create a machine with memory that has nil access in the target range
      machine_memory =
        PreMemory.init_nil_memory()
        # read access for pages 16...+99, the 100th page will have nil access
        |> PreMemory.set_access(16 * page_size(), 98 * page_size() + 1, :read)
        |> PreMemory.finalize()

      machine = %Integrated{
        memory: machine_memory,
        program: "program"
      }

      context = %Context{m: %{1 => machine}}
      memory = PreMemory.init_nil_memory() |> PreMemory.finalize()

      {:ok, context: context, gas: 100, registers: registers, memory: memory}
    end

    test "returns HUH when w10 = 3 and memory has nil access pages", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory
    } do
      registers = %{registers | r: put_elem(registers.r, 10, 3)}
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: ^context
             } = Refine.pages(gas, registers, memory, context)

      assert registers_[7] == huh
    end

    test "returns HUH when w10 = 4 and memory has nil access pages", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory
    } do
      registers = %{registers | r: put_elem(registers.r, 10, 4)}
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: ^context
             } = Refine.pages(gas, registers, memory, context)

      assert registers_[7] == huh
    end
  end

  describe "success cases" do
    setup do
      test_data = String.duplicate("A", 256)

      machine_memory =
        PreMemory.init_nil_memory()
        |> PreMemory.write(min_allowed_address(), test_data)
        |> PreMemory.set_access(16 * page_size(), 2 * page_size(), :read)
        |> PreMemory.finalize()

      machine = %Integrated{
        memory: machine_memory,
        program: "program"
      }

      context = %Context{m: %{1 => machine}}
      gas = 100

      # r7: machine ID, r8: start page, r9: page count
      registers = Registers.new(%{
        7 => 1,
        8 => 16,
        9 => 2
      })

      memory = PreMemory.init_nil_memory() |> PreMemory.finalize()

      {:ok,
       context: context,
       machine: machine,
       gas: gas,
       registers: registers,
       test_data: test_data,
       memory: memory}
    end

    test "r10 = 0 (zeroes and nil access pages)", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory
    } do
      registers = %{registers | r: put_elem(registers.r, 10, 0)}
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: context_
             } = Refine.pages(gas, registers, memory, context)

      assert registers_[7] == ok

      # Get updated machine
      machine = Map.get(context_.m, 1)
      page_size = machine.memory.page_size

      # Calculate range
      start_offset = registers[8] * page_size
      length = registers[9] * page_size

      # Verify pages have nil access
      refute Memory.check_range_access?(machine.memory, start_offset, length, :read)
    end

    test "r10 = 1 (zeroes and read access pages)", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      memory = %Memory{}
      registers = %{registers | r: put_elem(registers.r, 10, 1)}
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: context_
             } = Refine.pages(gas, registers, memory, context)

      assert registers_[7] == ok

      # Get updated machine
      machine = Map.get(context_.m, 1)
      page_size = machine.memory.page_size

      # Calculate range
      start_offset = registers[8] * page_size
      length = registers[9] * page_size

      # Verify pages are zeroed
      {:ok, zeroed_data} = Memory.read(machine.memory, start_offset, length)
      assert zeroed_data == <<0::size(length * 8)>>

      # Verify pages have read access
      assert Memory.check_range_access?(machine.memory, start_offset, length, :read)
      refute Memory.check_range_access?(machine.memory, start_offset, length, :write)
    end

    test "r10 = 2 (zeroes and write access pages)", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      memory = %Memory{}
      registers = %{registers | r: put_elem(registers.r, 10, 2)}
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: context_
             } = Refine.pages(gas, registers, memory, context)

      assert registers_[7] == ok

      # Get updated machine
      machine = Map.get(context_.m, 1)
      page_size = machine.memory.page_size

      # Calculate range
      start_offset = registers[8] * page_size
      length = registers[9] * page_size

      # Verify pages are zeroed
      {:ok, zeroed_data} = Memory.read(machine.memory, start_offset, length)
      assert zeroed_data == <<0::size(length * 8)>>

      # Verify pages have write access (which implies read access too)
      assert Memory.check_range_access?(machine.memory, start_offset, length, :write)
    end

    test "r10 = 3 (memory values did not change, read access pages)", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      test_data: test_data
    } do
      registers = %{registers | r: put_elem(registers.r, 10, 3)}
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: context_
             } = Refine.pages(gas, registers, memory, context)

      assert registers_[7] == ok

      # Get updated machine
      machine = Map.get(context_.m, 1)
      page_size = machine.memory.page_size

      # Calculate range
      start_offset = registers[8] * page_size
      length = byte_size(test_data)

      # Verify pages still contain original data (not zeroed)
      {:ok, unchanged_data} = Memory.read(machine.memory, start_offset, length)
      assert unchanged_data == test_data

      # Verify pages have read access
      assert Memory.check_range_access?(machine.memory, start_offset, length, :read)
      refute Memory.check_range_access?(machine.memory, start_offset, length, :write)
    end

    test "r10 = 4 (memory values did not change, write access pages)", %{
      gas: gas,
      registers: registers,
      memory: memory,
      test_data: test_data,
      context: context
    } do
      registers = %{registers | r: put_elem(registers.r, 10, 4)}
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: context_
             } = Refine.pages(gas, registers, memory, context)

      assert registers_[7] == ok

      # Get updated machine
      machine = Map.get(context_.m, 1)
      page_size = machine.memory.page_size

      # Calculate range
      start_offset = registers[8] * page_size
      length = byte_size(test_data)

      # Verify pages still contain original data (not zeroed)
      {:ok, unchanged_data} = Memory.read(machine.memory, start_offset, length)
      assert unchanged_data == test_data

      # Verify pages have write access
      assert Memory.check_range_access?(machine.memory, start_offset, length, :write)
    end
  end
end
