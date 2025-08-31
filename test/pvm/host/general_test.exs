defmodule PVM.Host.GeneralTest do
  use ExUnit.Case
  alias PVM.Host.General
  alias PVM.{Memory, Registers, PreMemory}
  alias System.State.ServiceAccount
  alias Util.Hash
  import PVM.Constants.HostCallResult

  @doc """
  Returns the base memory address used in tests.
  address below this will cause memory read/write to panic.
  """
  def a_0, do: PVM.Memory.Constants.min_allowed_address()

  describe "gas/4" do
    setup do
      m = %Memory{}
      c = %ServiceAccount{}
      {:ok, m: m, c: c}
    end

    test "returns remaining gas when continuing", %{m: m, c: c} do
      g = 100
      default_gas = PVM.Host.Gas.default_gas()
      remaining_gas = g - default_gas
      r = Registers.new()

      assert %{
               exit_reason: :continue,
               gas: ^remaining_gas,
               registers: registers_,
               memory: ^m,
               context: ^c
             } = General.gas(g, r, m, c)

      assert registers_[7] == remaining_gas
    end

    test "returns out of gas when gas is depleted", %{m: m, c: c} do
      r = Registers.new()

      assert %{
               exit_reason: :out_of_gas,
               gas: 0,
               registers: ^r,
               memory: ^m,
               context: ^c
             } = General.gas(0, r, m, c)
    end
  end

  describe "out of gas using" do
    setup do
      m = %Memory{}
      value = "value" |> String.pad_trailing(32, "\0")
      other_value = "other_value" |> String.pad_trailing(32, "\0")
      hash = Hash.default(value)
      other_hash = Hash.default(other_value)
      c = %ServiceAccount{preimage_storage_p: %{hash => value}}
      s = %{1 => %ServiceAccount{preimage_storage_p: %{other_hash => other_value}}}

      {:ok, m: m, c: c, s: s}
    end

    test "no change when out of gas", %{m: m, c: c, s: s} do
      r = Registers.new(%{7 => 1, 8 => 0})
      m = Memory.set_access(m, 0, 32, nil)
      result = General.lookup(9, r, m, c, 0, s)
      assert result.registers == r
      assert result.memory == m
      assert result.context == c
      assert result.exit_reason == :out_of_gas
      assert result.gas == 0
    end
  end

  describe "lookup/6" do
    setup do
      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.set_access(a_0(), 32, :write)
        |> PreMemory.finalize()

      value = "value" |> String.pad_trailing(32, "\0")
      other_value = "other_value" |> String.pad_trailing(32, "\0")
      hash = Hash.default(value)
      other_hash = Hash.default(other_value)
      service_account = %ServiceAccount{preimage_storage_p: %{hash => value}}
      services = %{1 => %ServiceAccount{preimage_storage_p: %{other_hash => other_value}}}
      gas = 100

      {:ok,
       memory: memory,
       service_account: service_account,
       services: services,
       gas: gas,
       hash: hash,
       other_hash: other_hash,
       value: value,
       other_value: other_value}
    end

    test "lookup uses service_account when service index is 0", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas,
      value: value,
      hash: hash
    } do
      {:ok, memory} = Memory.write(memory, a_0(), hash)
      o = a_0() + 100
      h = byte_size(value)

      # w7 = s = 0  => use service_account
      r = Registers.new(%{7 => 0, 8 => a_0(), 9 => o, 10 => 0, 11 => h})

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_
             } = General.lookup(gas, r, memory, service_account, 0, services)

      assert registers_[7] == h
      assert {:ok, ^value} = Memory.read(memory_, o, h)
    end

    test "lookup uses service_account when service index is max_64_bit", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas,
      value: value,
      hash: hash
    } do
      {:ok, memory} = Memory.write(memory, a_0(), hash)
      o = a_0() + 100
      h = byte_size(value)

      # w7 = 2^64 - 1  => use service_account
      r = Registers.new(%{7 => 0xFFFF_FFFF_FFFF_FFFF, 8 => a_0(), 9 => o, 10 => 0, 11 => h})

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_
             } = General.lookup(gas, r, memory, service_account, 0, services)

      assert registers_[7] == h
      assert {:ok, ^value} = Memory.read(memory_, o, h)
    end

    test "lookup uses different service when valid service index provided", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas,
      other_value: other_value,
      other_hash: other_hash
    } do
      {:ok, memory} = Memory.write(memory, a_0(), other_hash)
      o = a_0() + 100
      h = byte_size(other_value)

      # w7 = 1  => use services[1]
      r = Registers.new(%{7 => 1, 8 => a_0(), 9 => o, 10 => 0, 11 => h})

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_
             } = General.lookup(gas, r, memory, service_account, 0, services)

      assert registers_[7] == h
      assert {:ok, ^other_value} = Memory.read(memory_, o, h)
    end

    test "lookup returns none when service index does not exist", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas
    } do
      # w7 = 2  => use services[2] (none)
      r = Registers.new(%{7 => 2, 8 => a_0(), 9 => a_0() + 100})
      none = none()

      assert %{
               exit_reason: :continue,
                registers: registers_,
               memory: ^memory
             } = General.lookup(gas, r, memory, service_account, 0, services)

      assert registers_[7] == none
    end

    test "handles memory read failure", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas
    } do
      r = Registers.new(%{7 => 1, 8 => a_0(), 9 => a_0() + 100})
      memory = Memory.set_access(memory, a_0(), 32, nil)

      assert %{exit_reason: :panic, registers: registers_, memory: ^memory} =
               General.lookup(gas, r, memory, service_account, 0, services)

      assert registers_[7] == 1
    end

    test "handles memory write failure", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas,
      other_value: other_value,
      other_hash: other_hash
    } do
      {:ok, memory} = Memory.write(memory, a_0(), other_hash)
      memory = Memory.set_access(memory, a_0() + 100, 32, :read)
      o = a_0() + 100
      h = byte_size(other_value)

      # w7 = 1  => use services[1]
      r = Registers.new(%{7 => 1, 8 => a_0(), 9 => o, 10 => 0, 11 => h})

      assert %{exit_reason: :panic, registers: registers_, memory: ^memory} =
               General.lookup(gas, r, memory, service_account, 0, services)

      assert registers_[7] == 1
    end
  end

  describe "read/6" do
    setup do
      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.set_access(a_0(), 32, :write)
        |> PreMemory.finalize()

      value = "value" |> String.pad_trailing(32, "\0")
      key = "key" |> String.pad_trailing(32, "\0")
      other_value = "other_value" |> String.pad_trailing(32, "\0")
      other_key = "other_key" |> String.pad_trailing(32, "\0")

      storage_key = other_storage_key = <<0::28*8>>
      service_account = %ServiceAccount{storage: HashedKeysMap.new(%{storage_key => value})}

      services = %{
        1 => %ServiceAccount{storage: HashedKeysMap.new(%{other_storage_key => other_value})}
      }

      gas = 100

      {:ok,
       memory: memory,
       service_account: service_account,
       services: services,
       gas: gas,
       key: key,
       value: value,
       other_key: other_key,
       other_value: other_value}
    end

    test "read uses service_account when service index is max_64_bit", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas,
      value: value
    } do
      ko = a_0() + 100
      kz = 28
      o = a_0() + 200
      v = byte_size(value)

      r = Registers.new(%{7 => 0xFFFF_FFFF_FFFF_FFFF, 8 => ko, 9 => kz, 10 => o, 11 => 0, 12 => 300})

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_
             } = General.read(gas, r, memory, service_account, 0, services)

      assert registers_[7] == v
      assert {:ok, ^value} = Memory.read(memory_, o, v)
    end

    test "read uses different service when valid service index provided", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas,
      other_value: other_value
    } do
      ko = a_0() + 100
      kz = 28
      o = a_0() + 200
      v = byte_size(other_value)

      r = Registers.new(%{7 => 1, 8 => ko, 9 => kz, 10 => o, 11 => 0, 12 => 300})

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_
             } = General.read(gas, r, memory, service_account, 0, services)

      assert registers_[7] == v
      assert {:ok, ^other_value} = Memory.read(memory_, o, v)
    end

    test "read returns none when service index does not exist", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas
    } do
      ko = a_0() + 100
      kz = 28
      o = a_0() + 200

      r = Registers.new(%{7 => 2, 8 => ko, 9 => kz, 10 => o, 11 => 0, 12 => 300})
      none = none()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory
             } = General.read(gas, r, memory, service_account, 0, services)

      assert registers_[7] == none
    end

    test "handles key not in storage", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas
    } do
      ko = a_0() + 100
      kz = 28
      o = a_0() + 200
      {:ok, memory} = Memory.write(memory, ko, <<0xAA::32-little>>)

      r = Registers.new(%{7 => 0xFFFF_FFFF_FFFF_FFFF, 8 => ko, 9 => kz, 10 => o, 11 => 0, 12 => 300})
      none = none()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory
             } = General.read(gas, r, memory, service_account, 0, services)

      assert registers_[7] == none
    end

    test "handles memory read failure", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas
    } do
      ko = a_0() + 100
      kz = 28
      r = Registers.new(%{7 => 1, 8 => ko, 9 => kz})
      memory = Memory.set_access(memory, ko, kz, nil)

      assert %{
               exit_reason: :panic,
               registers: registers_,
               memory: ^memory
             } = General.read(gas, r, memory, service_account, 0, services)

      assert registers_[7] == 1
    end

    test "handles memory write failure", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas
    } do
      ko = a_0() + 100
      kz = 28
      o = a_0() + 200
      memory = Memory.set_access(memory, o, 1, :read)

      r = Registers.new(%{7 => 0xFFFF_FFFF_FFFF_FFFF, 8 => ko, 9 => kz, 10 => o, 11 => 0, 12 => 300})

      assert %{
               exit_reason: :panic,
               registers: registers_,
               memory: ^memory
             } = General.read(gas, r, memory, service_account, 0, services)

      assert registers_[7] == 0xFFFF_FFFF_FFFF_FFFF
    end
  end

  describe "write/5" do
    setup do
      value = "value" |> String.pad_trailing(32, "\0")
      key = "key" |> String.pad_trailing(28, "\0")
      c = %ServiceAccount{storage: HashedKeysMap.new(%{key => value}), balance: 2000}
      g = 100

      registers = Registers.new(%{
        7 => a_0(),
        8 => 28,
        9 => a_0() + %Memory{}.page_size + 100,
        10 => 32
      })

      m =
        PreMemory.init_nil_memory()
        |> PreMemory.write(a_0(), key)
        |> PreMemory.write(a_0() + %Memory{}.page_size + 100, value)
        # |> PreMemory.set_access(a_0(), 32, :write)
        # |> PreMemory.set_access(a_0() + %Memory{}.page_size, 32, :write)

        |> PreMemory.finalize()

      {:ok, m: m, c: c, g: g, registers: registers, storage_key: key}
    end

    test "returns panic when key memory read fails", %{m: m, c: c, g: g, registers: registers} do
      assert %{exit_reason: :panic, memory: ^m, context: ^c} =
               General.write(g, registers, m, c, 0)
    end

    test "returns panic when value memory read fails", %{m: m, c: c, g: g, registers: registers} do
      assert %{exit_reason: :panic, memory: ^m, context: ^c} =
               General.write(g, registers, m, c, 1)
    end

    test "successfully updates storage with new value", %{
      m: m,
      g: g,
      c: c,
      storage_key: storage_key,
      registers: registers
    } do
      new_value = "new_value" |> String.pad_trailing(32, "\0")

      m =
        Memory.set_access_by_page(m, 16, 2, :write)
        |> Memory.write!(registers[9], new_value)
        |> Memory.set_access_by_page(16, 2, :read)

      service_account = %{c | storage: HashedKeysMap.new(%{storage_key => "b"})}

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^m,
               context: result_context
             } = General.write(g, registers, m, service_account, 1)

      assert registers_[7] == 1
      assert get_in(result_context, [:storage, storage_key]) == new_value
    end

    test "successfully removes key when vz is 0", %{
      m: m,
      c: c,
      g: g,
      storage_key: storage_key,
      registers: registers
    } do
      m = Memory.set_access_by_page(m, 16, 1, :read)
      registers = %{registers | r: put_elem(registers.r, 10, 0)}
      l = get_in(c, [:storage, storage_key]) |> byte_size()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^m,
               context: result_context
             } = General.write(g, registers, m, c, 1)

      assert registers_[7] == l
      assert get_in(result_context, [:storage, storage_key]) == nil
    end

    test "returns FULL when threshold exceeded", %{m: m, c: c, g: g, registers: registers} do
      new_value = "new_value" |> String.pad_trailing(32, "\0")

      m =
        Memory.set_access_by_page(m, 16, 2, :write)
        |> Memory.write!(registers[9], new_value)
        |> Memory.set_access_by_page(16, 2, :read)

      service_account = %{c | balance: 50}
      full = full()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^m,
               context: ^service_account
             } = General.write(g, registers, m, service_account, 1)

      assert registers_[7] == full
    end
  end

  describe "info/6" do
    setup do
      m =
        PreMemory.init_nil_memory()
        |> PreMemory.set_access(a_0(), 128, :write)
        |> PreMemory.finalize()

      service_account = %ServiceAccount{
        code_hash: "code_hash",
        balance: 1000,
        gas_limit_g: 100,
        gas_limit_m: 200
      }

      services = %{
        1 => service_account
      }

      g = 100
      registers = Registers.new(%{7 => 1, 8 => a_0(), 9 => 0, 10 => 1000})
      context = %ServiceAccount{}

      {:ok,
       m: m,
       service_account: service_account,
       services: services,
       g: g,
       context: context,
       registers: registers}
    end

    test "returns none when service doesn't exist", %{
      m: m,
      services: services,
      g: g,
      context: context,
      registers: registers
    } do
      r = %{registers | r: put_elem(registers.r, 7, 999)}
      none = none()

      assert %{exit_reason: :continue, registers: registers_, memory: ^m, context: ^context} =
               General.info(g, r, m, context, 42, services)

      assert registers_[7] == none
    end

    test "panics when memory write fails", %{
      m: m,
      services: services,
      g: g,
      context: context,
      registers: registers
    } do
      # Make memory write fail
      m = Memory.set_access(m, a_0(), 32, :read)

      assert %{exit_reason: :panic, memory: ^m, context: ^context} =
               General.info(g, registers, m, context, 42, services)
    end

    test "successfully writes service info using service index", %{
      m: m,
      services: services,
      g: g,
      context: context,
      registers: registers
    } do
      t = Map.get(services, 1)

      expected_encoded_data =
        <<
          t.code_hash::binary,
          t.balance::64-little,
          ServiceAccount.threshold_balance(t)::64-little,
          t.gas_limit_g::64-little,
          t.gas_limit_m::64-little,
          t.storage.octets_in_storage::64-little,
          t.storage.items_in_storage::32-little,
          t.deposit_offset::64-little,
          t.creation_slot::32-little,
          t.last_accumulation_slot::32-little,
          t.parent_service::32-little
        >>

      expected_size = byte_size(expected_encoded_data)

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.info(g, registers, m, context, 42, services)

      assert registers_[7] == expected_size
      assert Memory.read!(memory_, a_0(), expected_size) == expected_encoded_data
    end

    test "successfully writes service info using max 64-bit value", %{
      m: m,
      services: services,
      g: g,
      context: context,
      registers: registers
    } do
      # selects service from args rather than registers
      r = %{registers | r: put_elem(registers.r, 7, 0xFFFF_FFFF_FFFF_FFFF)}

      t = Map.get(services, 1)

      expected_encoded_data =
        <<
          t.code_hash::binary,
          t.balance::64-little,
          ServiceAccount.threshold_balance(t)::64-little,
          t.gas_limit_g::64-little,
          t.gas_limit_m::64-little,
          t.storage.octets_in_storage::64-little,
          t.storage.items_in_storage::32-little,
          t.deposit_offset::64-little,
          t.creation_slot::32-little,
          t.last_accumulation_slot::32-little,
          t.parent_service::32-little
        >>

      expected_size = byte_size(expected_encoded_data)

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.info(g, r, m, context, 1, services)

      assert registers_[7] == expected_size
      assert Memory.read!(memory_, a_0(), expected_size) == expected_encoded_data
    end
  end

  describe "log/6" do
    setup do
      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.set_access(a_0() + 0x1000, 32, :write)
        |> PreMemory.set_access(a_0() + 0x2000, 32, :write)
        |> PreMemory.finalize()

      target = "bootstrap-refine"
      message = "Hello world!"
      core_index = 1
      service_index = 42

      memory =
        Memory.write!(memory, a_0() + 0x1000, target)
        |> Memory.write!(a_0() + 0x2000, message)
        |> Memory.set_access(a_0() + 0x1000, 32, :read)
        |> Memory.set_access(a_0() + 0x2000, 32, :read)

      {:ok,
       memory: memory,
       target: target,
       message: message,
       core_index: core_index,
       service_index: service_index}
    end

    @tag :log
    test "logs with DEBUG level and all parts", %{
      memory: memory,
      target: target,
      message: message,
      core_index: core_index,
      service_index: service_index
    } do
      g = 100

      r = Registers.new(%{
        7 => 1,
        8 => a_0() + 0x1000,
        9 => byte_size(target),
        10 => a_0() + 0x2000,
        11 => byte_size(message)
      })

      assert %{exit_reason: :continue, gas: 100, registers: ^r, memory: ^memory, context: nil} =
               General.log(g, r, memory, nil, core_index, service_index)
    end

    @tag :log
    test "logs with missing core and service indices", %{
      memory: memory,
      message: message,
      target: target
    } do
      g = 100

      r = Registers.new(%{
        7 => 2,
        8 => a_0() + 0x1000,
        9 => byte_size(target),
        10 => a_0() + 0x2000,
        11 => byte_size(message)
      })

      assert %{exit_reason: :continue, gas: 100, registers: ^r, memory: ^memory, context: nil} =
               General.log(g, r, memory, nil, nil, nil)
    end

    @tag :log
    test "handles memory read errors gracefully" do
      mem = PreMemory.init_nil_memory() |> PreMemory.finalize()
      g = 100
      r = Registers.new(%{7 => 4, 8 => a_0() + 0x1000, 9 => 10, 10 => a_0() + 0x2000, 11 => 15})

      # Function should continue even with memory read errors
      assert %{exit_reason: :continue, gas: 100, registers: ^r, memory: ^mem, context: nil} =
               General.log(g, r, mem, nil, 5, 99)
    end

    @tag :log
    test "logs with zero target address and length", %{memory: memory, message: message} do
      g = 100
      r = Registers.new(%{7 => 2, 8 => 0, 9 => 0, 10 => a_0() + 0x2000, 11 => byte_size(message)})

      # Test that the function executes successfully with zero target address
      assert %{exit_reason: :continue, gas: 100, registers: ^r, memory: ^memory, context: nil} =
               General.log(g, r, memory, nil, 1, 42)
    end
  end
end
