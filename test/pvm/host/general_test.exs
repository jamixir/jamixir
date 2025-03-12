defmodule PVM.Host.GeneralTest do
  use ExUnit.Case
  alias PVM.Host.General
  alias PVM.{Memory, Registers}
  alias System.State.ServiceAccount
  alias Util.Hash
  import PVM.Constants.HostCallResult
  use Codec.Encoder

  @doc """
  Returns the base memory address used in tests.
  address below this will cause memory read/write to panic.
  """
  def a_0, do: 0x1_0000

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
      r = %Registers{}

      assert %{
               exit_reason: :continue,
               gas: ^remaining_gas,
               registers: %{r7: ^remaining_gas},
               memory: ^m,
               context: ^c
             } = General.gas(g, r, m, c)
    end

    test "returns out of gas when gas is depleted", %{m: m, c: c} do
      r = %Registers{}

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
      m = %Memory{} |> Memory.set_default_access(:write)
      value = "value" |> String.pad_trailing(32, "\0")
      other_value = "other_value" |> String.pad_trailing(32, "\0")
      hash = Hash.default(value)
      other_hash = Hash.default(other_value)
      c = %ServiceAccount{preimage_storage_p: %{hash => value}}
      s = %{1 => %ServiceAccount{preimage_storage_p: %{other_hash => other_value}}}

      {:ok, m: m, c: c, s: s}
    end

    test "no change when out of gas", %{m: m, c: c, s: s} do
      r = %Registers{r7: 1, r8: 0}
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
      memory = %Memory{} |> Memory.set_default_access(:write)
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
      r = %Registers{r7: 0, r8: a_0(), r9: o, r10: 0, r11: h}

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^h},
               memory: memory_
             } = General.lookup(gas, r, memory, service_account, 0, services)

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
      r = %Registers{r7: 0xFFFF_FFFF_FFFF_FFFF, r8: a_0(), r9: o, r10: 0, r11: h}

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^h},
               memory: memory_
             } = General.lookup(gas, r, memory, service_account, 0, services)

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
      r = %Registers{r7: 1, r8: a_0(), r9: o, r10: 0, r11: h}

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^h},
               memory: memory_
             } = General.lookup(gas, r, memory, service_account, 0, services)

      assert {:ok, ^other_value} = Memory.read(memory_, o, h)
    end

    test "lookup returns none when service index does not exist", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas
    } do
      # w7 = 2  => use services[2] (none)
      r = %Registers{r7: 2, r8: a_0()}
      none = none()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^none},
               memory: ^memory
             } = General.lookup(gas, r, memory, service_account, 0, services)
    end

    test "handles memory read failure", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas
    } do
      r = %Registers{r7: 1, r8: a_0()}
      memory = Memory.set_access(memory, a_0(), 32, nil)

      assert %{exit_reason: :panic, registers: %{r7: 1}, memory: ^memory} =
               General.lookup(gas, r, memory, service_account, 0, services)
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
      r = %Registers{r7: 1, r8: a_0(), r9: o, r10: 0, r11: h}

      assert %{exit_reason: :panic, registers: %{r7: 1}, memory: ^memory} =
               General.lookup(gas, r, memory, service_account, 0, services)
    end
  end

  describe "read/6" do
    setup do
      memory = %Memory{} |> Memory.set_default_access(:write)
      value = "value" |> String.pad_trailing(32, "\0")
      key = "key" |> String.pad_trailing(32, "\0")
      other_value = "other_value" |> String.pad_trailing(32, "\0")
      other_key = "other_key" |> String.pad_trailing(32, "\0")

      storage_key = Hash.default(Hash.zero())
      other_storage_key = Hash.default(<<1::32-little, 0::28*8>>)

      service_account = %ServiceAccount{storage: %{storage_key => value}}
      services = %{1 => %ServiceAccount{storage: %{other_storage_key => other_value}}}
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

      r = %Registers{r7: 0xFFFF_FFFF_FFFF_FFFF, r8: ko, r9: kz, r10: o, r11: 0, r12: 300}

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^v},
               memory: memory_
             } = General.read(gas, r, memory, service_account, 0, services)

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

      r = %Registers{r7: 1, r8: ko, r9: kz, r10: o, r11: 0, r12: 300}

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^v},
               memory: memory_
             } = General.read(gas, r, memory, service_account, 0, services)

      assert {:ok, ^other_value} = Memory.read(memory_, o, v)
    end

    test "read returns none when service index does not exist", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas
    } do
      r = %Registers{r7: 2, r8: a_0()}
      none = none()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^none},
               memory: ^memory
             } = General.read(gas, r, memory, service_account, 0, services)
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

      r = %Registers{r7: 0xFFFF_FFFF_FFFF_FFFF, r8: ko, r9: kz, r10: o, r11: 0, r12: 300}
      none = none()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^none},
               memory: ^memory
             } = General.read(gas, r, memory, service_account, 0, services)
    end

    test "handles memory read failure", %{
      memory: memory,
      service_account: service_account,
      services: services,
      gas: gas
    } do
      ko = a_0() + 100
      kz = 28
      r = %Registers{r7: 1, r8: ko, r9: kz}
      memory = Memory.set_access(memory, ko, kz, nil)

      assert %{
               exit_reason: :panic,
               registers: %{r7: 1},
               memory: ^memory
             } = General.read(gas, r, memory, service_account, 0, services)
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

      r = %Registers{r7: 0xFFFF_FFFF_FFFF_FFFF, r8: ko, r9: kz, r10: o, r11: 0, r12: 300}

      assert %{
               exit_reason: :panic,
               registers: %{r7: 0xFFFF_FFFF_FFFF_FFFF},
               memory: ^memory
             } = General.read(gas, r, memory, service_account, 0, services)
    end
  end

  describe "write/5" do
    setup do
      value = "value" |> String.pad_trailing(32, "\0")
      key = "key" |> String.pad_trailing(28, "\0")
      storage_key = Hash.default(<<1::32-little>> <> key)
      c = %ServiceAccount{storage: %{storage_key => value}, balance: 2000}
      g = 100

      registers = %Registers{
        r7: a_0(),
        r8: 28,
        r9: a_0() + %Memory{}.page_size + 100,
        r10: 32
      }

      m =
        %Memory{}
        |> Memory.set_default_access(:write)
        |> Memory.write!(a_0(), key)
        |> Memory.write!(a_0() + %Memory{}.page_size + 100, value)

      {:ok, m: m, c: c, g: g, registers: registers, storage_key: storage_key}
    end

    test "returns panic when key memory read fails", %{m: m, c: c, g: g, registers: registers} do
      m = Memory.set_default_access(m, nil)

      assert %{exit_reason: :panic, memory: ^m, context: ^c} =
               General.write(g, registers, m, c, 0)
    end

    test "returns panic when value memory read fails", %{m: m, c: c, g: g, registers: registers} do
      m = Memory.set_access(m, registers.r9, registers.r10, nil)

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
      m = Memory.write!(m, registers.r9, new_value)

      service_account = %{c | storage: %{storage_key => "b"}}

      assert %{
               exit_reason: :continue,
               registers: %{r7: 1},
               memory: ^m,
               context: result_context
             } = General.write(g, registers, m, service_account, 1)

      assert get_in(result_context, [:storage, storage_key]) == new_value
    end

    test "successfully removes key when vz is 0", %{
      m: m,
      c: c,
      g: g,
      storage_key: storage_key,
      registers: registers
    } do
      registers = %{registers | r10: 0}
      l = get_in(c, [:storage, storage_key]) |> byte_size()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: ^m,
               context: result_context
             } = General.write(g, registers, m, c, 1)

      assert get_in(result_context, [:storage, storage_key]) == nil
    end

    test "returns FULL when threshold exceeded", %{m: m, c: c, g: g, registers: registers} do
      new_value = "new_value" |> String.pad_trailing(32, "\0")
      m = Memory.write!(m, registers.r9, new_value)

      service_account = %{c | balance: 50}
      full = full()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^full},
               memory: ^m,
               context: ^service_account
             } = General.write(g, registers, m, service_account, 1)
    end
  end

  describe "info/6" do
    setup do
      m = %Memory{} |> Memory.set_default_access(:write)

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
      registers = %Registers{r7: 1, r8: a_0()}
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
      r = Registers.set(registers, :r7, 999)
      none = none()

      assert %{exit_reason: :continue, registers: %{r7: ^none}, memory: ^m, context: ^context} =
               General.info(g, r, m, context, 42, services)
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
      ok = ok()

      assert %{exit_reason: :continue, registers: %{r7: ^ok}, memory: memory_, context: ^context} =
               General.info(g, registers, m, context, 42, services)

      t = Map.get(services, 1)

      expected_mem_value =
        e(
          [t.code_hash, t.balance, ServiceAccount.threshold_balance(t), t.gas_limit_g,
           t.gas_limit_m, ServiceAccount.octets_in_storage(t), ServiceAccount.items_in_storage(t)],
          [:binary, :balance, :balance, :gas, :gas, :account_octets, :account_items]
        )

      assert Memory.read!(memory_, a_0(), byte_size(expected_mem_value)) == expected_mem_value
    end

    test "successfully writes service info using max 64-bit value", %{
      m: m,
      services: services,
      g: g,
      context: context,
      registers: registers
    } do
      # selects service from args rather than registers
      Registers.set(registers, :r7, 0xFFFF_FFFF_FFFF_FFFF)

      ok = ok()

      assert %{exit_reason: :continue, registers: %{r7: ^ok}, memory: memory_, context: ^context} =
               General.info(g, registers, m, context, 1, services)

      t = Map.get(services, 1)

      expected_mem_value =
        e(
          [t.code_hash, t.balance, ServiceAccount.threshold_balance(t), t.gas_limit_g,
           t.gas_limit_m, ServiceAccount.octets_in_storage(t), ServiceAccount.items_in_storage(t)],
          [:binary, :balance, :balance, :gas, :gas, :account_octets, :account_items]
        )

      assert Memory.read!(memory_, a_0(), byte_size(expected_mem_value)) == expected_mem_value
    end
  end
end
